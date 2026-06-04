import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_session_guard.dart';
import 'package:trip_planner_app/features/notifications/services/notification_service.dart';
import 'package:trip_planner_app/features/trip_detail/data/parking_spot_service.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_service.dart';
import 'package:trip_planner_app/features/trips/data/invite_member_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_member.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_realtime_service.dart';
import 'package:trip_planner_app/features/trips/data/trip_service.dart';
import 'package:trip_planner_app/features/trips/data/trip_snapshot_cache.dart';

class TripStore extends ChangeNotifier {
  TripStore._();

  static final TripStore instance = TripStore._();

  final List<TripSummary> _trips = [];
  final Map<String, List<TripMember>> _membersByTripId = {};
  final TripService _tripService = TripService.instance;
  final StopService _stopService = StopService.instance;
  final ParkingSpotService _parkingSpotService = ParkingSpotService.instance;
  final TripRealtimeService _realtimeService = TripRealtimeService.instance;
  final TripSnapshotCache _snapshotCache = TripSnapshotCache.instance;

  Future<void>? _loadFuture;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _hasCachedData = false;
  DateTime? _lastSyncedAt;
  Object? _loadError;
  String? _cacheUserId;

  /// Monotonically-increasing token that is incremented each time
  /// [clearForSignOut] is called.  [_loadTrips] captures the value at the
  /// start of every load and discards its results if the token has changed by
  /// the time the async work completes (i.e. a sign-out raced the in-flight
  /// load).
  int _sessionToken = 0;

  List<TripSummary> get trips => List<TripSummary>.unmodifiable(_trips);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get hasCachedData => _hasCachedData;
  bool get isRefreshing => _isLoading && _trips.isNotEmpty;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  Object? get loadError => _loadError;

  Future<void> ensureLoaded({bool force = false}) {
    if (_isLoading && _loadFuture != null) {
      return _loadFuture!;
    }
    if (_isInitialized && !force) {
      return Future.value();
    }

    final future = _loadTrips(loadCacheFirst: !force);
    _loadFuture = future;
    return future;
  }

  Future<void> reloadTrips() {
    return ensureLoaded(force: true);
  }

  TripSummary? findById(String id) {
    for (final trip in _trips) {
      if (trip.id == id) {
        return trip;
      }
    }
    return null;
  }

  TripDay? findDay(String tripId, String dayId) {
    final trip = findById(tripId);
    if (trip == null) {
      return null;
    }

    for (final day in trip.days) {
      if (day.id == dayId) {
        return day;
      }
    }

    return null;
  }

  StopItem? findStop(String tripId, String dayId, String stopId) {
    final day = findDay(tripId, dayId);
    if (day == null) {
      return null;
    }

    for (final stop in day.stops) {
      if (stop.id == stopId) {
        return stop;
      }
    }

    return null;
  }

  Future<StopItem> addStop({
    required String tripId,
    required String dayId,
    required StopItem stop,
  }) async {
    final location = _findEditableDayLocation(tripId, dayId);
    if (location == null) {
      throw StateError('Trip or day not found, or trip is read-only.');
    }

    final draft =
        _normalizeStopDraft(stop, sortOrder: location.day.stops.length);
    final savedStop = await _saveStop(location.day.id, draft);
    final updatedStops = _normalizeStops([...location.day.stops, savedStop]);
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: updatedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _withSessionGuard(
      () => _stopService.reorderStops(
        dayId: location.day.id,
        stops: updatedStops,
      ),
    );
    await _refreshTripReminders(updatedTrip);
    _persistSnapshotInBackground();
    notifyListeners();
    return updatedStops.firstWhere((item) => item.id == savedStop.id,
        orElse: () => savedStop);
  }

  Future<StopItem> updateStop({
    required String tripId,
    required String dayId,
    required StopItem stop,
  }) async {
    final location = _findEditableDayLocation(tripId, dayId);
    if (location == null) {
      throw StateError('Trip or day not found, or trip is read-only.');
    }

    final stopIndex =
        location.day.stops.indexWhere((item) => item.id == stop.id);
    if (stopIndex == -1) {
      throw StateError('Stop not found.');
    }

    final existingStop = location.day.stops[stopIndex];
    final draft = _normalizeStopDraft(
      stop.copyWith(id: existingStop.id),
      sortOrder: existingStop.sortOrder,
    );

    final savedStop = await _updateStopWithParking(
      previous: existingStop,
      next: draft,
    );

    final nextStops = [...location.day.stops]..[stopIndex] = savedStop;
    final updatedStops = existingStop.timeLabel == savedStop.timeLabel
        ? _normalizeStopsInCurrentOrder(nextStops)
        : _normalizeStops(nextStops);
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: updatedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _withSessionGuard(
      () => _stopService.reorderStops(
        dayId: location.day.id,
        stops: updatedStops,
      ),
    );
    await _refreshTripReminders(updatedTrip);
    _persistSnapshotInBackground();
    notifyListeners();
    return updatedStops.firstWhere((item) => item.id == savedStop.id,
        orElse: () => savedStop);
  }

  Future<void> reorderStops({
    required String tripId,
    required String dayId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final location = _findEditableDayLocation(tripId, dayId);
    if (location == null) {
      throw StateError('Trip or day not found, or trip is read-only.');
    }

    final stops = [...location.day.stops];
    if (oldIndex < 0 ||
        oldIndex >= stops.length ||
        newIndex < 0 ||
        newIndex > stops.length) {
      return;
    }

    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }

    final movedStop = stops.removeAt(oldIndex);
    stops.insert(targetIndex, movedStop);
    final reorderedStops = _normalizeStopsInCurrentOrder(stops);
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: reorderedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _withSessionGuard(
      () => _stopService.reorderStops(
        dayId: location.day.id,
        stops: reorderedStops,
      ),
    );
    await _refreshTripReminders(updatedTrip);
    _persistSnapshotInBackground();
    notifyListeners();
  }

  Future<bool> deleteStop({
    required String tripId,
    required String dayId,
    required String stopId,
  }) async {
    final location = _findEditableDayLocation(tripId, dayId);
    if (location == null) {
      return false;
    }

    final stopIndex =
        location.day.stops.indexWhere((item) => item.id == stopId);
    if (stopIndex == -1) {
      return false;
    }

    final stop = location.day.stops[stopIndex];
    if (stop.id == null || stop.id!.isEmpty) {
      return false;
    }

    await _withSessionGuard(() => _stopService.deleteStop(stop.id!));
    final updatedStops = _normalizeStopsInCurrentOrder(
        [...location.day.stops]..removeAt(stopIndex));
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: updatedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _withSessionGuard(
      () => _stopService.reorderStops(
        dayId: location.day.id,
        stops: updatedStops,
      ),
    );
    await _refreshTripReminders(updatedTrip);
    _persistSnapshotInBackground();
    notifyListeners();
    return true;
  }

  /// Update the in-memory photo list for a stop after uploads/deletions.
  /// Does NOT touch the database — photo persistence is handled by
  /// [StopPhotoService] before this is called.
  void updateStopPhotos({
    required String tripId,
    required String dayId,
    required String stopId,
    required List<StopPhoto> photos,
  }) {
    final location = _findEditableDayLocation(tripId, dayId);
    if (location == null) return;

    final stopIndex =
        location.day.stops.indexWhere((item) => item.id == stopId);
    if (stopIndex == -1) return;

    final updatedStop = location.day.stops[stopIndex].copyWith(photos: photos);
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(
        stops: [...location.day.stops]..[stopIndex] = updatedStop,
      ),
    );
    _trips[location.tripIndex] = updatedTrip;
    _persistSnapshotInBackground();
    notifyListeners();
  }

  Future<ParkingSpot> addParkingSpot({
    required String tripId,
    required String dayId,
    required String stopId,
    required ParkingSpot parkingSpot,
  }) async {
    final stop = findStop(tripId, dayId, stopId);
    if (stop == null) {
      throw StateError('Stop not found.');
    }

    final savedStop = await updateStop(
      tripId: tripId,
      dayId: dayId,
      stop: stop.copyWith(parkingSpots: [...stop.parkingSpots, parkingSpot]),
    );

    return savedStop.parkingSpots.last;
  }

  Future<void> updateParkingSpot({
    required String tripId,
    required String dayId,
    required String stopId,
    required ParkingSpot parkingSpot,
  }) async {
    final stop = findStop(tripId, dayId, stopId);
    if (stop == null) {
      throw StateError('Stop not found.');
    }

    final parkingIndex =
        stop.parkingSpots.indexWhere((item) => item.id == parkingSpot.id);
    if (parkingIndex == -1) {
      throw StateError('Parking spot not found.');
    }

    final updatedParkingSpots = [...stop.parkingSpots]..[parkingIndex] =
        parkingSpot;
    await updateStop(
      tripId: tripId,
      dayId: dayId,
      stop: stop.copyWith(parkingSpots: updatedParkingSpots),
    );
  }

  Future<void> removeParkingSpot({
    required String tripId,
    required String dayId,
    required String stopId,
    required String parkingSpotId,
  }) async {
    final stop = findStop(tripId, dayId, stopId);
    if (stop == null) {
      throw StateError('Stop not found.');
    }

    final updatedParkingSpots =
        stop.parkingSpots.where((item) => item.id != parkingSpotId).toList();
    await updateStop(
      tripId: tripId,
      dayId: dayId,
      stop: stop.copyWith(parkingSpots: updatedParkingSpots),
    );
  }

  Future<TripSummary> createTrip({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? color,
  }) async {
    final trip = await _withSessionGuardNoRetry(
      () => _tripService.createTrip(
        title: title,
        startDate: startDate,
        endDate: endDate,
        color: color,
      ),
    );

    _trips.insert(0, trip);
    await NotificationService.instance.scheduleTripReminders(trip);
    _persistSnapshotInBackground();
    notifyListeners();
    return trip;
  }

  /// Invite a user to a trip by their email address (owner-only).
  Future<InviteMemberResult> inviteMemberByEmail(
    String tripId,
    String email,
    TripPermission permission,
  ) async {
    return _withSessionGuardNoRetry(
      () => _tripService.inviteMemberByEmail(tripId, email, permission),
    );
  }

  Future<bool> deleteTrip(String tripId) async {
    final index = _trips
        .indexWhere((trip) => trip.id == tripId && trip.role == TripRole.owner);
    if (index == -1) {
      return false;
    }

    final deleted =
        await _withSessionGuard(() => _tripService.deleteOwnedTrip(tripId));
    if (!deleted) {
      return false;
    }

    _trips.removeAt(index);
    await NotificationService.instance.cancelTripReminders(tripId);
    _persistSnapshotInBackground();
    notifyListeners();
    return true;
  }

  Future<bool> leaveSharedTrip(String tripId) async {
    final index = _trips
        .indexWhere((trip) => trip.id == tripId && trip.role == TripRole.guest);
    if (index == -1) {
      return false;
    }

    final left =
        await _withSessionGuard(() => _tripService.leaveSharedTrip(tripId));
    if (!left) {
      return false;
    }

    _trips.removeAt(index);
    await NotificationService.instance.cancelTripReminders(tripId);
    _persistSnapshotInBackground();
    notifyListeners();
    return true;
  }

  Future<bool> updateTripColor(String tripId, String? color) async {
    final index = _trips.indexWhere(
      (trip) => trip.id == tripId && trip.canEdit,
    );
    if (index == -1) {
      return false;
    }

    await _withSessionGuard(() => _tripService.updateTripColor(tripId, color));
    _trips[index] = _trips[index].copyWith(color: color);
    _persistSnapshotInBackground();
    notifyListeners();
    return true;
  }

  /// Fetch the member list for [tripId] (owner-only operation).
  Future<List<TripMember>> fetchTripMembers(String tripId) async {
    final members =
        await _withSessionGuard(() => _tripService.fetchTripMembers(tripId));
    _membersByTripId[tripId] = members;
    return members;
  }

  List<TripMember>? cachedMembers(String tripId) => _membersByTripId[tripId];

  /// Update a member's permission (owner-only).
  Future<void> updateMemberPermission(
    String tripId,
    String userId,
    TripPermission permission,
  ) async {
    await _withSessionGuard(
      () => _tripService.updateMemberPermission(tripId, userId, permission),
    );
    final members = _membersByTripId[tripId];
    if (members != null) {
      _membersByTripId[tripId] = [
        for (final m in members)
          m.userId == userId ? m.copyWith(permission: permission) : m,
      ];
      notifyListeners();
    }
  }

  /// Remove a member from the trip (owner-only).
  Future<void> removeMember(String tripId, String userId) async {
    await _withSessionGuard(() => _tripService.removeMember(tripId, userId));
    final members = _membersByTripId[tripId];
    if (members != null) {
      _membersByTripId[tripId] =
          members.where((m) => m.userId != userId).toList();
      notifyListeners();
    }
  }

  void resetForTests() {
    _sessionToken++;
    _trips.clear();
    _membersByTripId.clear();
    NotificationService.instance.resetForTests();
    _realtimeService.unsubscribe();
    _loadFuture = null;
    _isLoading = false;
    _isInitialized = false;
    _hasCachedData = false;
    _lastSyncedAt = null;
    _loadError = null;
    _cacheUserId = null;
    notifyListeners();
  }

  /// Clears all cached data and cancels the Realtime subscription.
  /// Call this whenever the current user signs out so that the next user
  /// starts with a clean slate and the old Realtime channel is released.
  ///
  /// The session token is incremented synchronously before any async work so
  /// that any in-flight [_loadTrips] call will see the changed token and
  /// discard its results rather than repopulating the store.
  Future<void> clearForSignOut() async {
    _sessionToken++; // synchronous – happens before any await
    final userIdToClear =
        _cacheUserId ?? Supabase.instance.client.auth.currentUser?.id;
    await _realtimeService.unsubscribe();
    if (userIdToClear != null) {
      await _snapshotCache.clearForUser(userIdToClear);
    }
    _trips.clear();
    _membersByTripId.clear();
    NotificationService.instance.clearTrackedReminders();
    _loadFuture = null;
    _isLoading = false;
    _isInitialized = false;
    _hasCachedData = false;
    _lastSyncedAt = null;
    _loadError = null;
    _cacheUserId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Flutter's dispose() is synchronous and cannot be made async.
    // unsubscribe() is fire-and-forget here; errors are caught and logged so
    // they don't become noisy unhandled zone-level exceptions during teardown.
    // The main cleanup path for production code is clearForSignOut(), which
    // does await the unsubscribe.
    unawaited(
      _realtimeService.unsubscribe().catchError((Object error, StackTrace st) {
        debugPrint('TripStore.dispose: unsubscribe failed: $error');
      }),
    );
    super.dispose();
  }

  Future<void> _loadTrips({required bool loadCacheFirst}) async {
    // Capture the session token at the start.  If clearForSignOut() is called
    // while this load is in-flight, the token will be incremented and we will
    // discard the stale results rather than repopulating the store.
    final token = _sessionToken;
    Session? session;
    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (error) {
      _loadError = error;
      _isInitialized = true;
      _isLoading = false;
      _loadFuture = null;
      notifyListeners();
      return;
    }
    var userId = session?.user.id;
    if (userId == null || userId.isEmpty) {
      await _handleExpiredSession();
      return;
    }
    if (session!.isExpired &&
        !await SupabaseSessionGuard.refreshCurrentSessionIfExpired()) {
      _cacheUserId = userId;
      await _handleExpiredSession();
      return;
    }
    session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      _cacheUserId = userId;
      await _handleExpiredSession();
      return;
    }
    userId = session.user.id;
    if (userId.isEmpty) {
      await _handleExpiredSession();
      return;
    }
    _cacheUserId = userId;

    if (loadCacheFirst && !_isInitialized && _trips.isEmpty) {
      await _loadCachedSnapshot(userId: userId, token: token);
      if (_sessionToken != token) return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final loadedTrips = await _withSessionGuard(
        _tripService.fetchTripsForCurrentUser,
      );

      // If the session changed while we were waiting, discard results.
      if (_sessionToken != token) return;

      _trips
        ..clear()
        ..addAll(loadedTrips);
      _loadError = null;
      _isInitialized = true;
      _hasCachedData = false;
      NotificationService.instance.clearTrackedReminders();
      for (final trip in _trips) {
        await NotificationService.instance.scheduleTripReminders(trip);
      }
      // Guard again: reminders scheduling is also async.
      if (_sessionToken != token) return;

      final syncedAt = DateTime.now();
      await _snapshotCache.saveForUser(userId, _trips, savedAt: syncedAt);
      _lastSyncedAt = syncedAt;

      // Subscribe to Realtime for permission/removal changes.
      await _realtimeService.subscribe(
        onPermissionChanged: _onPermissionChanged,
        onRemovedFromTrip: _onRemovedFromTrip,
      );

      // Final guard: drop the notifyListeners() if the session changed.
      if (_sessionToken != token) return;
    } catch (error) {
      if (_sessionToken != token) return;
      if (SupabaseSessionGuard.isSessionExpiredError(error)) {
        await _handleExpiredSession();
        return;
      }
      _loadError = error;
      _isInitialized = true;
    } finally {
      if (_sessionToken == token) {
        _isLoading = false;
        _loadFuture = null;
        notifyListeners();
      }
    }
  }

  Future<void> _loadCachedSnapshot({
    required String userId,
    required int token,
  }) async {
    final snapshot = await _snapshotCache.loadForUser(userId);
    if (_sessionToken != token || snapshot == null) {
      return;
    }

    _trips
      ..clear()
      ..addAll(snapshot.trips);
    _isInitialized = true;
    _hasCachedData = true;
    _lastSyncedAt = snapshot.savedAt;
    _loadError = null;
    notifyListeners();
  }

  void _persistSnapshotInBackground() {
    String? userId = _cacheUserId;
    if (userId == null || userId.isEmpty) {
      try {
        userId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {
        return;
      }
    }
    if (userId == null || userId.isEmpty) {
      return;
    }

    final tripsSnapshot = List<TripSummary>.unmodifiable(_trips);
    final savedAt = DateTime.now();
    _lastSyncedAt = savedAt;
    _hasCachedData = false;
    unawaited(
      _snapshotCache
          .saveForUser(userId, tripsSnapshot, savedAt: savedAt)
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Failed to persist trip snapshot: $error');
      }),
    );
  }

  Future<T> _withSessionGuard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (!SupabaseSessionGuard.isSessionExpiredError(error)) {
        rethrow;
      }
      if (await SupabaseSessionGuard.refreshCurrentSessionIfExpired(
        forceRefresh: true,
      )) {
        try {
          return await action();
        } catch (retryError, retryStackTrace) {
          if (SupabaseSessionGuard.isSessionExpiredError(retryError)) {
            await _handleExpiredSession();
          }
          Error.throwWithStackTrace(retryError, retryStackTrace);
        }
      }
      await _handleExpiredSession();
      rethrow;
    }
  }

  Future<T> _withSessionGuardNoRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (!SupabaseSessionGuard.isSessionExpiredError(error)) {
        rethrow;
      }
      if (!await SupabaseSessionGuard.refreshCurrentSessionIfExpired(
        forceRefresh: true,
      )) {
        await _handleExpiredSession();
      }
      rethrow;
    }
  }

  Future<void> _handleExpiredSession() async {
    final userId =
        _cacheUserId ?? Supabase.instance.client.auth.currentUser?.id;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Failed to sign out after expired session: $error');
    }

    await clearForSignOut();
    if (userId != null && userId != _cacheUserId) {
      await _snapshotCache.clearForUser(userId);
    }
  }

  void _onPermissionChanged(String tripId, TripPermission permission) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return;
    _trips[index] = _trips[index].copyWith(permission: permission);
    _persistSnapshotInBackground();
    notifyListeners();
  }

  void _onRemovedFromTrip(String tripId) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return;
    _trips.removeAt(index);
    _membersByTripId.remove(tripId);
    NotificationService.instance.cancelTripReminders(tripId);
    _persistSnapshotInBackground();
    notifyListeners();
  }

  Future<void> _refreshTripReminders(TripSummary trip) async {
    await NotificationService.instance.scheduleTripReminders(trip);
  }

  Future<StopItem> _saveStop(String dayId, StopItem stop) async {
    final createdStop = await _withSessionGuardNoRetry(
      () => _stopService.createStop(
        dayId: dayId,
        stop: stop.copyWith(id: null, parkingSpots: const []),
      ),
    );
    final parkingSpots = await _syncParkingSpots(
      stopId: createdStop.id!,
      previous: const [],
      next: stop.parkingSpots,
    );
    return createdStop.copyWith(
      parkingSpots: parkingSpots,
      photos: stop.photos,
      sortOrder: stop.sortOrder,
    );
  }

  Future<StopItem> _updateStopWithParking({
    required StopItem previous,
    required StopItem next,
  }) async {
    if (next.id == null || next.id!.isEmpty) {
      throw StateError('Stop id is required for update.');
    }

    final updatedStop = await _withSessionGuard(
      () => _stopService.updateStop(next.copyWith(parkingSpots: const [])),
    );
    final parkingSpots = await _syncParkingSpots(
      stopId: next.id!,
      previous: previous.parkingSpots,
      next: next.parkingSpots,
    );
    return updatedStop.copyWith(
      parkingSpots: parkingSpots,
      photos: next.photos,
      sortOrder: next.sortOrder,
    );
  }

  Future<List<ParkingSpot>> _syncParkingSpots({
    required String stopId,
    required List<ParkingSpot> previous,
    required List<ParkingSpot> next,
  }) async {
    final normalized = _normalizeParkingSpots(next);
    final previousIds =
        previous.map((item) => item.id).whereType<String>().toSet();

    // Create / update all spots in parallel to reduce round-trip latency.
    final saved = await Future.wait(
      normalized.map((parkingSpot) async {
        if (parkingSpot.id != null && previousIds.contains(parkingSpot.id)) {
          final updated = await _withSessionGuard(
            () => _parkingSpotService.updateParkingSpot(parkingSpot),
          );
          return updated.copyWith(sortOrder: parkingSpot.sortOrder);
        } else {
          final created = await _withSessionGuardNoRetry(
            () => _parkingSpotService.createParkingSpot(
              stopId: stopId,
              parkingSpot: parkingSpot.copyWith(id: null),
            ),
          );
          return created.copyWith(sortOrder: parkingSpot.sortOrder);
        }
      }),
    );

    // Delete removed spots in parallel.
    final savedIds = saved.map((item) => item.id).whereType<String>().toSet();
    await Future.wait([
      for (final removed in previous)
        if (removed.id != null && !savedIds.contains(removed.id))
          _withSessionGuard(
            () => _parkingSpotService.deleteParkingSpot(removed.id!),
          ),
    ]);

    await _withSessionGuard(
      () => _parkingSpotService.reorderParkingSpots(
        stopId: stopId,
        parkingSpots: saved,
      ),
    );
    return saved;
  }

  StopItem _normalizeStopDraft(StopItem stop, {required int sortOrder}) {
    return stop.copyWith(
      sortOrder: sortOrder,
      parkingSpots: _normalizeParkingSpots(stop.parkingSpots),
    );
  }

  List<ParkingSpot> _normalizeParkingSpots(List<ParkingSpot> parkingSpots) {
    return [
      for (var index = 0; index < parkingSpots.length; index += 1)
        parkingSpots[index].copyWith(sortOrder: index),
    ];
  }

  List<StopItem> _normalizeStops(List<StopItem> stops) {
    final orderedStops = sortStopsChronologically(stops);
    return [
      for (var index = 0; index < orderedStops.length; index += 1)
        orderedStops[index].copyWith(sortOrder: index),
    ];
  }

  List<StopItem> _normalizeStopsInCurrentOrder(List<StopItem> stops) {
    return [
      for (var index = 0; index < stops.length; index += 1)
        stops[index].copyWith(sortOrder: index),
    ];
  }

  _DayLocation? _findEditableDayLocation(String tripId, String dayId) {
    final tripIndex =
        _trips.indexWhere((trip) => trip.id == tripId && trip.canEdit);
    if (tripIndex == -1) {
      return null;
    }

    final trip = _trips[tripIndex];
    final dayIndex = trip.days.indexWhere((day) => day.id == dayId);
    if (dayIndex == -1) {
      return null;
    }

    return _DayLocation(
      tripIndex: tripIndex,
      dayIndex: dayIndex,
      trip: trip,
      day: trip.days[dayIndex],
    );
  }

  TripSummary _replaceDayAt(TripSummary trip, int dayIndex, TripDay day) {
    final days = [...trip.days]..[dayIndex] = day;
    return trip.copyWith(days: days);
  }
}

class _DayLocation {
  const _DayLocation({
    required this.tripIndex,
    required this.dayIndex,
    required this.trip,
    required this.day,
  });

  final int tripIndex;
  final int dayIndex;
  final TripSummary trip;
  final TripDay day;
}
