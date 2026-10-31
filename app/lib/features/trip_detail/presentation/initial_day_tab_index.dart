import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

/// Selects today's itinerary day, or the first tab when no date matches.
int initialDayTabIndex(List<TripDay> days, DateTime now) {
  final today = now.toLocal();
  final index = days.indexWhere((day) {
    final date = day.date;
    return date != null &&
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
  });
  return index < 0 ? 0 : index;
}
