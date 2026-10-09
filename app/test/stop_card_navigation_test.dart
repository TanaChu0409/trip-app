import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/stop_card.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  testWidgets('stop card keeps map details without navigation actions',
      (WidgetTester tester) async {
    const stop = StopItem(
      id: 'stop-1',
      title: '景點',
      mapUrl: 'https://maps.example.com/stop',
      parkingSpots: [
        ParkingSpot(
          id: 'parking-1',
          name: '附近停車場',
          mapUrl: 'https://maps.example.com/parking',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StopCard(
              stop: stop,
              tripColor: null,
              isReadOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('景點'), findsOneWidget);
    expect(find.text('附近停車場'), findsNWidgets(2));
    expect(find.text('開啟地圖'), findsNothing);
    expect(find.text('導航'), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
