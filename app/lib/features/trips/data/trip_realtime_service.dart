import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

typedef PermissionChangedCallback = void Function(
  String tripId,
  TripPermission permission,
);
typedef RemovedFromTripCallback = void Function(String tripId);

/// Subscribes to Supabase Realtime changes on `shared_access` rows that
/// belong to the current user, so that:
///  - When the owner updates `permission`, the store is notified immediately.
///  - When the owner removes the user, the store removes the trip immediately.
class TripRealtimeService {
  TripRealtimeService._();

  static final TripRealtimeService instance = TripRealtimeService._();

  RealtimeChannel? _channel;
  PermissionChangedCallback? _onPermissionChanged;
  RemovedFromTripCallback? _onRemovedFromTrip;

  Future<void> subscribe({
    required PermissionChangedCallback onPermissionChanged,
    required RemovedFromTripCallback onRemovedFromTrip,
  }) async {
    // Always clean up any existing channel before creating a new one so that
    // repeated calls to subscribe() (e.g. from reloadTrips()) never leave
    // stale channels open.
    await unsubscribe();

    _onPermissionChanged = onPermissionChanged;
    _onRemovedFromTrip = onRemovedFromTrip;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    _channel = client
        .channel('shared_access:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shared_access',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            final tripId = newRow['trip_id'] as String?;
            final permissionStr = newRow['permission'] as String?;
            if (tripId != null) {
              _onPermissionChanged?.call(
                tripId,
                tripPermissionFromBackend(permissionStr),
              );
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'shared_access',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final oldRow = payload.oldRecord;
            final tripId = oldRow['trip_id'] as String?;
            if (tripId != null) {
              _onRemovedFromTrip?.call(tripId);
            }
          },
        )
        .subscribe();
  }

  Future<void> unsubscribe() async {
    if (_channel != null) {
      await Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
    _onPermissionChanged = null;
    _onRemovedFromTrip = null;
  }
}
