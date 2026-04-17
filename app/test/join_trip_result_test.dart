import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trips/data/join_trip_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  group('joinTripByCodeStatusFromBackend', () {
    test('maps backend success status', () {
      expect(
        joinTripByCodeStatusFromBackend('success'),
        JoinTripByCodeStatus.success,
      );
    });

    test('maps backend already joined status', () {
      expect(
        joinTripByCodeStatusFromBackend('already_joined'),
        JoinTripByCodeStatus.alreadyJoined,
      );
    });

    test('falls back to trip not found for unknown backend status', () {
      expect(
        joinTripByCodeStatusFromBackend('unexpected'),
        JoinTripByCodeStatus.tripNotFound,
      );
      expect(
        joinTripByCodeStatusFromBackend(null),
        JoinTripByCodeStatus.tripNotFound,
      );
    });
  });

  group('tripPermissionFromBackend', () {
    test('maps editor', () {
      expect(
        tripPermissionFromBackend('editor'),
        TripPermission.editor,
      );
    });

    test('maps viewer', () {
      expect(
        tripPermissionFromBackend('viewer'),
        TripPermission.viewer,
      );
    });

    test('defaults to editor for unknown value', () {
      expect(
        tripPermissionFromBackend(null),
        TripPermission.editor,
      );
      expect(
        tripPermissionFromBackend('unknown'),
        TripPermission.editor,
      );
    });
  });
}
