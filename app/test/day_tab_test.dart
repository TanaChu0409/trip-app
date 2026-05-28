import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/day_tab.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  testWidgets('day timeline shows stops without a time',
      (WidgetTester tester) async {
    const day = TripDay(
      id: 'day-1',
      label: '第一天',
      dateLabel: '5/20',
      subtitle: '測試行程日',
      stops: [
        StopItem(id: 'stop-1', title: '早餐', timeLabel: '08:30'),
        StopItem(id: 'stop-2', title: '還沒排時間'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTab(
            tripId: 'trip-1',
            day: day,
            tripColor: null,
            isReadOnly: true,
            isActive: true,
            onAddButtonVisibilityChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('還沒排時間'), findsOneWidget);
    expect(find.text('未排定'), findsOneWidget);
  });
}
