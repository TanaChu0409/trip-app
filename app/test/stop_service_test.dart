import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_service.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('update stop sends colour name changes and the default empty map',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'fake-test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/update_stop_with_color_names');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return http.Response(
          jsonEncode({'id': body['p_stop_id'], ...body['p_stop'] as Map}),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() => Supabase.instance.dispose());

    const stop = StopItem(id: 'stop-1', title: '地點', color: '#123456');
    final saved = await StopService.instance.updateStop(
      stop,
      colorNames: {'#123456': '海洋藍', '#ABCDEF': '新名稱'},
    );
    expect(requests.single['p_stop_id'], stop.id);
    expect(requests.single['p_stop'], stop.toJson());
    expect(requests.single['p_color_names'], {
      '#123456': '海洋藍',
      '#ABCDEF': '新名稱',
    });
    expect(saved.id, stop.id);
    expect(saved.color, stop.color);

    await StopService.instance.updateStop(stop);
    expect(requests.last['p_color_names'], isEmpty);
  });
}
