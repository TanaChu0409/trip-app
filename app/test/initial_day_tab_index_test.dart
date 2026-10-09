import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/initial_day_tab_index.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

TripDay day(DateTime? date) => TripDay(
      id: 'day',
      label: 'day',
      dateLabel: '1/1',
      subtitle: '',
      stops: [],
      date: date,
    );

void main() {
  final days = [
    day(DateTime(2026, 12, 31)),
    day(DateTime(2027, 1, 1)),
    day(DateTime(2027, 1, 2))
  ];

  test('selects first, middle and last day using the full calendar date', () {
    for (var index = 0; index < days.length; index++) {
      final date = days[index].date!;
      expect(
          initialDayTabIndex(
              days, DateTime(date.year, date.month, date.day, 23, 59)),
          index);
    }
  });

  test('defaults to first before, after, or in a different year', () {
    for (final date in [
      DateTime(2026, 12, 30),
      DateTime(2027, 1, 3),
      DateTime(2028, 1, 1)
    ]) {
      expect(initialDayTabIndex(days, date), 0);
    }
  });

  test('defaults to first for empty, missing, or unmatched dates', () {
    final today = DateTime(2027, 1, 1);
    expect(initialDayTabIndex([], today), 0);
    expect(initialDayTabIndex([day(null)], today), 0);
    expect(initialDayTabIndex([days.first, days.last], today), 0);
  });

  test('converts the current instant to local time and picks first match', () {
    final today = DateTime(2027, 1, 1, 23);
    expect(
        initialDayTabIndex([day(null), day(today), day(today)], today.toUtc()),
        1);
  });

  test('date survives copyWith and cache roundtrip; old cache is readable', () {
    final original = day(DateTime(2027, 1, 1));
    expect(original.copyWith(label: 'updated').date, original.date);
    expect(original.copyWith(date: DateTime(2028, 1, 1)).date,
        DateTime(2028, 1, 1));
    expect(TripDay.fromCacheJson(original.toCacheJson()).date, original.date);
    final legacy = original.toCacheJson()..remove('date');
    expect(TripDay.fromCacheJson(legacy).date, isNull);
  });
}
