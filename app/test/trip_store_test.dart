import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  test('stop item json roundtrip preserves fields', () {
    const stop = StopItem(
      id: 'stop-1',
      title: '嘉義站',
      timeLabel: '9:5',
      note: '測試備註',
      badge: '午餐',
      mapUrl: 'https://example.com',
      isHighlight: true,
      sortOrder: 2,
    );

    final restored = StopItem.fromJson(stop.toJson());

    expect(restored.id, 'stop-1');
    expect(restored.title, '嘉義站');
    expect(restored.timeLabel, '09:05');
    expect(restored.note, '測試備註');
    expect(restored.badge, '午餐');
    expect(restored.mapUrl, 'https://example.com');
    expect(restored.isHighlight, isTrue);
    expect(restored.sortOrder, 2);
  });

  test('trip summary stop count aggregates nested stops', () {
    const trip = TripSummary(
      id: 'trip-1',
      title: '測試旅程',
      dateRange: '2026/05/01 - 2026/05/02',
      role: TripRole.owner,
      days: [
        TripDay(
          id: 'day-1',
          label: '第一天',
          dateLabel: '5/1',
          subtitle: '說明',
          stops: [
            StopItem(title: 'A'),
            StopItem(title: 'B'),
          ],
        ),
        TripDay(
          id: 'day-2',
          label: '第二天',
          dateLabel: '5/2',
          subtitle: '說明',
          stops: [StopItem(title: 'C')],
        ),
      ],
    );

    expect(trip.stopCount, 3);
  });
}
