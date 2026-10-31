import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_http_client.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_photo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real services correlate edits, session retry and photo-failure rollback',
      () async {
    SharedPreferences.setMockInitialValues({});
    final log = DiagnosticLog.instance..clear();
    const userId = '00000000-0000-4000-8000-000000000001';
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    String jwtPart(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final accessToken = '${jwtPart({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${jwtPart({
          'sub': userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'exp': exp
        })}.fake-signature';
    final session = {
      'access_token': accessToken,
      'refresh_token': 'private-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp,
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'private@example.com',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z'
      },
    };
    final trip = {
      'id': 'private-trip-id',
      'owner_id': userId,
      'title': '私人旅行',
      'start_date': '2026-11-01',
      'end_date': '2026-11-01',
      'share_code': 'private-code',
      'is_archived': false
    };
    final day = {
      'id': 'private-day-id',
      'trip_id': 'private-trip-id',
      'date': '2026-11-01',
      'label': '第一天',
      'subtitle': '',
      'sort_order': 0
    };
    var stopRow = <String, dynamic>{
      'id': 'private-stop-id',
      'day_id': 'private-day-id',
      'title': '私密地點',
      'sort_order': 0,
      'is_highlight': false
    };
    var failFirstUpdate = true;
    var refreshCount = 0;
    final transport = MockClient((request) async {
      Object? data;
      final path = request.url.path;
      if (path == '/auth/v1/token') {
        refreshCount++;
        data = session;
      } else if (path == '/rest/v1/trips') {
        data = request.method == 'POST' ? trip : [trip];
      } else if (path == '/rest/v1/days') {
        if (request.method == 'POST') return http.Response('', 201);
        data = [day];
      } else if (path.endsWith('/create_stop_with_palette')) {
        data = stopRow;
      } else if (path.endsWith('/update_stop_with_palette')) {
        if (failFirstUpdate) {
          failFirstUpdate = false;
          return http.Response(
              jsonEncode({'code': 'PGRST301', 'message': 'JWT expired'}), 401,
              headers: {'content-type': 'application/json'});
        }
        final body = jsonDecode(request.body) as Map;
        stopRow = {
          ...stopRow,
          ...(body['p_stop'] as Map).cast<String, dynamic>()
        };
        data = stopRow;
      } else if (path == '/rest/v1/stops') {
        if (request.method == 'PATCH') return http.Response('', 204);
        data = <Object>[];
      } else if (path.startsWith('/storage/v1/object/')) {
        return http.Response(
            jsonEncode({
              'statusCode': '403',
              'error': 'Forbidden',
              'message':
                  'new row violates row-level security private@example.com'
            }),
            403,
            headers: {'content-type': 'application/json'});
      } else {
        fail('Unexpected fixture request: ${request.method} $path');
      }
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'});
    });
    await Supabase.initialize(
        url: 'http://127.0.0.1:1',
        anonKey: 'fake-test-key',
        httpClient: DiagnosticHttpClient(transport),
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false, detectSessionInUri: false));
    addTearDown(() async {
      TripStore.instance.resetForTests();
      await Supabase.instance.dispose();
      log.clear();
    });
    await Supabase.instance.client.auth.recoverSession(jsonEncode(session));
    final store = TripStore.instance;
    await store.createTrip(
        title: '私人旅行',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 1));
    final original = await store.addStop(
        tripId: 'private-trip-id',
        dayId: 'private-day-id',
        stop: const StopItem(title: '私密地點', sortOrder: 0));
    log.clear();
    await log.trace('儲存地點與照片', () async {
      await store.updateStop(
          tripId: 'private-trip-id',
          dayId: 'private-day-id',
          stop: original.copyWith(title: '更新後的私密地點'));
      try {
        await StopPhotoService.instance.compressAndUpload(
            stopId: 'private-stop-id',
            tripId: 'private-trip-id',
            sortOrder: 0,
            bytes: Uint8List.fromList(
                img.encodeJpg(img.Image(width: 2, height: 2))));
        fail('The photo fixture must fail');
      } catch (error) {
        expect(error, isA<StorageException>());
        await log.trace(
            '還原地點變更',
            () => store.updateStop(
                tripId: 'private-trip-id',
                dayId: 'private-day-id',
                stop: original));
        log.markFailed();
      }
    });
    expect(refreshCount, 1);
    expect(
        store
            .findStop('private-trip-id', 'private-day-id', 'private-stop-id')!
            .title,
        '私密地點');
    final entries = log.entries;
    expect(entries.where((e) => e.label == '登入刷新後重試'), hasLength(1));
    expect(
        entries.where((e) => e.label == '還原地點變更：結束' && e.outcome == 'success'),
        hasLength(1));
    expect(entries.last.outcome, 'failure');
    final requests = entries.where((e) => e.kind == 'request').toList();
    expect(requests.length, greaterThan(5));
    expect(
        requests.map((e) => e.toJson()['operationId']).toSet(), hasLength(1));
    for (final secret in [
      '私人旅行',
      '私密地點',
      'private@example.com',
      'private-trip-id',
      'private-day-id',
      'private-stop-id',
      'private-refresh-token',
      accessToken,
      'fake-test-key'
    ]) {
      expect(log.export(), isNot(contains(secret)));
    }
    // Allow fire-and-forget cache writes to finish before the fixture disposes.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}
