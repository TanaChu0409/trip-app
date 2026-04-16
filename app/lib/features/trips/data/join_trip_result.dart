import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

enum JoinTripByCodeStatus { success, tripNotFound, alreadyJoined }

class JoinTripByCodeResult {
  const JoinTripByCodeResult({required this.status, this.trip});

  final JoinTripByCodeStatus status;
  final TripSummary? trip;

  bool get isSuccess => status == JoinTripByCodeStatus.success && trip != null;
}
