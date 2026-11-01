import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/stop_card.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final calls = <MethodCall>[];
  Future<Object?> Function()? handler;
  var taps = 0;
  setUp(() {
    calls.clear();
    taps = 0;
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler == null ? true : await handler!();
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> pumpCard(WidgetTester tester,
      {String? url = ' https://maps.example.com/stop ',
      String parkingUrl = ' https://maps.example.com/parking ',
      bool readOnly = false,
      bool archived = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StopCard(
      stop: StopItem(id: 'stop', title: '景點', mapUrl: url, parkingSpots: [
        ParkingSpot(id: 'parking', name: '停車場 A', mapUrl: parkingUrl)
      ]),
      tripColor: null,
      isReadOnly: readOnly,
      isArchived: archived,
      onTap: () => taps++,
    )))));
  }

  for (final state in ['editable', 'readOnly', 'archived']) {
    testWidgets('map buttons launch externally for $state without editing',
        (tester) async {
      await pumpCard(tester,
          readOnly: state != 'editable', archived: state == 'archived');
      for (final label in ['開啟地圖', '導航']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(calls.map((c) => c.method), ['launch', 'launch']);
      expect(calls.map((c) => (c.arguments as Map)['url']), [
        'https://maps.example.com/stop',
        'https://maps.example.com/parking'
      ]);
      for (final call in calls) {
        expect((call.arguments as Map)['useSafariVC'], false);
        expect((call.arguments as Map)['useWebView'], false);
      }
      expect(taps, 0);
    });
  }
  for (final url in <String?>[null, '', '   ']) {
    testWidgets('hide absent or blank links: $url', (tester) async {
      await pumpCard(tester, url: url, parkingUrl: url ?? '');
      expect(find.text('開啟地圖'), findsNothing);
      expect(find.text('導航'), findsNothing);
      expect(find.text('停車場 A'), findsOneWidget);
    });
  }
  for (final label in ['開啟地圖', '導航']) {
    for (final throwsError in [false, true]) {
      testWidgets('$label handles failure with exception=$throwsError',
          (tester) async {
        handler = () async {
          if (throwsError) throw PlatformException(code: 'launch_failed');
          return false;
        };
        await pumpCard(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('無法開啟地圖連結'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('completion after disposal is safe', (tester) async {
    final result = Completer<Object?>();
    handler = () => result.future;
    await pumpCard(tester);
    await tester.tap(find.text('開啟地圖'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    result.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
