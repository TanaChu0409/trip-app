import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final Map<String, Set<int>> _tripNotificationIds = {};

  Future<void> initialize() async {
    // Hook flutter_local_notifications here after the Flutter SDK is available.
  }

  Future<void> scheduleTripReminders(TripSummary trip) async {
    final notificationIds = <int>{};
    var index = 0;

    for (final day in trip.days) {
      for (final stop in day.stops) {
        index += 1;
        notificationIds.add(_buildNotificationId(trip.id, '${day.id}-${stop.title}-$index'));
      }
    }

    _tripNotificationIds[trip.id] = notificationIds;
  }

  Future<void> cancelTripReminders(String tripId) async {
    _tripNotificationIds.remove(tripId);
  }

  bool hasTripReminders(String tripId) {
    final notificationIds = _tripNotificationIds[tripId];
    return notificationIds != null && notificationIds.isNotEmpty;
  }

  int trackedReminderCount(String tripId) {
    return _tripNotificationIds[tripId]?.length ?? 0;
  }

  void resetForTests() {
    _tripNotificationIds.clear();
  }

  int _buildNotificationId(String tripId, String suffix) {
    return Object.hash(tripId, suffix) & 0x7fffffff;
  }
}
