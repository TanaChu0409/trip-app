import 'package:flutter/foundation.dart';
import 'package:trip_planner_app/features/notifications/services/notification_service.dart';
import 'package:trip_planner_app/features/trip_detail/data/parking_spot_service.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_service.dart';
import 'package:trip_planner_app/features/trips/data/join_trip_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_member.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_realtime_service.dart';
import 'package:trip_planner_app/features/trips/data/trip_service.dart';

class TripStore extends ChangeNotifier {
  TripStore._();

  static final TripStore instance = TripStore._();

  final List<TripSummary> _trips = [];
  final Map<String, List<TripMember>> _membersByTripId = {};
  final TripService _tripService = TripService.instance;
  final StopService _stopService = StopService.instance;
  final ParkingSpotService _parkingSpotService = ParkingSpotService.instance;
  final TripRealtimeService _realtimeService = TripRealtimeService.instance;

  Future<void>? _loadFuture;
  bool _isLoading = false;
  bool _isInitialized = false;
  Object? _loadError;

  List<TripSummary> get trips => List<TripSummary>.unmodifiable(_trips);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  Object? get loadError => _loadError;

  Future<void> ensureLoaded({bool force = false}) {
    if (_isLoading && _loadFuture != null) {
      return _loadFuture!;
    }
    if (_isInitialized && !force) {
      return Future.value();
    }

    final future = _loadTrips();
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
    await _stopService.reorderStops(
        dayId: location.day.id, stops: updatedStops);
    await _refreshTripReminders(updatedTrip);
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

    final updatedStops = _normalizeStops(
      [...location.day.stops]..[stopIndex] = savedStop,
    );
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: updatedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _stopService.reorderStops(
        dayId: location.day.id, stops: updatedStops);
    await _refreshTripReminders(updatedTrip);
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
    final reorderedStops = _normalizeStops(stops);
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: reorderedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _stopService.reorderStops(
        dayId: location.day.id, stops: reorderedStops);
    await _refreshTripReminders(updatedTrip);
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

    await _stopService.deleteStop(stop.id!);
    final updatedStops =
        _normalizeStops([...location.day.stops]..removeAt(stopIndex));
    final updatedTrip = _replaceDayAt(
      location.trip,
      location.dayIndex,
      location.day.copyWith(stops: updatedStops),
    );

    _trips[location.tripIndex] = updatedTrip;
    await _stopService.reorderStops(
        dayId: location.day.id, stops: updatedStops);
    await _refreshTripReminders(updatedTrip);
    notifyListeners();
    return true;
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
    final trip = await _tripService.createTrip(
      title: title,
      startDate: startDate,
      endDate: endDate,
      color: color,
    );

    _trips.insert(0, trip);
    await NotificationService.instance.scheduleTripReminders(trip);
    notifyListeners();
    return trip;
  }

  Future<JoinTripByCodeResult> joinTripByCode(String rawCode) async {
    final result = await _tripService.joinTripByCode(rawCode);
    if (!result.isSuccess || result.trip == null) {
      return result;
    }

    _trips.removeWhere((trip) => trip.id == result.trip!.id);
    _trips.add(result.trip!);
    await NotificationService.instance.scheduleTripReminders(result.trip!);
    notifyListeners();
    return result;
  }

  Future<bool> deleteTrip(String tripId) async {
    final index = _trips
        .indexWhere((trip) => trip.id == tripId && trip.role == TripRole.owner);
    if (index == -1) {
      return false;
    }

    final deleted = await _tripService.deleteOwnedTrip(tripId);
    if (!deleted) {
      return false;
    }

    _trips.removeAt(index);
    await NotificationService.instance.cancelTripReminders(tripId);
    notifyListeners();
    return true;
  }

  Future<bool> leaveSharedTrip(String tripId) async {
    final index = _trips
        .indexWhere((trip) => trip.id == tripId && trip.role == TripRole.guest);
    if (index == -1) {
      return false;
    }

    final left = await _tripService.leaveSharedTrip(tripId);
    if (!left) {
      return false;
    }

    _trips.removeAt(index);
    await NotificationService.instance.cancelTripReminders(tripId);
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

    await _tripService.updateTripColor(tripId, color);
    _trips[index] = _trips[index].copyWith(color: color);
    notifyListeners();
    return true;
  }

  /// Fetch the member list for [tripId] (owner-only operation).
  Future<List<TripMember>> fetchTripMembers(String tripId) async {
    final members = await _tripService.fetchTripMembers(tripId);
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
    await _tripService.updateMemberPermission(tripId, userId, permission);
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
    await _tripService.removeMember(tripId, userId);
    final members = _membersByTripId[tripId];
    if (members != null) {
      _membersByTripId[tripId] =
          members.where((m) => m.userId != userId).toList();
      notifyListeners();
    }
  }

  void resetForTests() {
    _trips.clear();
    _membersByTripId.clear();
    NotificationService.instance.resetForTests();
    _realtimeService.unsubscribe();
    _loadFuture = null;
    _isLoading = false;
    _isInitialized = false;
    _loadError = null;
    notifyListeners();
  }

  /// Clears all cached data and cancels the Realtime subscription.
  /// Call this whenever the current user signs out so that the next user
  /// starts with a clean slate and the old Realtime channel is released.
  Future<void> clearForSignOut() async {
    await _realtimeService.unsubscribe();
    _trips.clear();
    _membersByTripId.clear();
    NotificationService.instance.resetForTests();
    _loadFuture = null;
    _isLoading = false;
    _isInitialized = false;
    _loadError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Flutter's dispose() is synchronous and cannot be made async.
    // Calling unsubscribe() here starts the async cleanup; the Future is
    // intentionally not awaited.  The main cleanup path for production code
    // is clearForSignOut(), which does await the unsubscribe.
    _realtimeService.unsubscribe();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    _isLoading = true;
    if (!_isInitialized) {
      notifyListeners();
    }

    try {
      final loadedTrips = await _tripService.fetchTripsForCurrentUser();
      _trips
        ..clear()
        ..addAll(loadedTrips);
      _loadError = null;
      _isInitialized = true;
      NotificationService.instance.resetForTests();
      for (final trip in _trips) {
        await NotificationService.instance.scheduleTripReminders(trip);
      }
      // Subscribe to Realtime for permission/removal changes.
      await _realtimeService.subscribe(
        onPermissionChanged: _onPermissionChanged,
        onRemovedFromTrip: _onRemovedFromTrip,
      );
    } catch (error) {
      _loadError = error;
      _isInitialized = true;
    } finally {
      _isLoading = false;
      _loadFuture = null;
      notifyListeners();
    }
  }

  void _onPermissionChanged(String tripId, TripPermission permission) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return;
    _trips[index] = _trips[index].copyWith(permission: permission);
    notifyListeners();
  }

  void _onRemovedFromTrip(String tripId) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return;
    _trips.removeAt(index);
    _membersByTripId.remove(tripId);
    NotificationService.instance.cancelTripReminders(tripId);
    notifyListeners();
  }

  Future<void> _refreshTripReminders(TripSummary trip) async {
    await NotificationService.instance.scheduleTripReminders(trip);
  }

  Future<StopItem> _saveStop(String dayId, StopItem stop) async {
    final createdStop = await _stopService.createStop(
      dayId: dayId,
      stop: stop.copyWith(id: null, parkingSpots: const []),
    );
    final parkingSpots = await _syncParkingSpots(
      stopId: createdStop.id!,
      previous: const [],
      next: stop.parkingSpots,
    );
    return createdStop.copyWith(
        parkingSpots: parkingSpots, sortOrder: stop.sortOrder);
  }

  Future<StopItem> _updateStopWithParking({
    required StopItem previous,
    required StopItem next,
  }) async {
    if (next.id == null || next.id!.isEmpty) {
      throw StateError('Stop id is required for update.');
    }

    final updatedStop =
        await _stopService.updateStop(next.copyWith(parkingSpots: const []));
    final parkingSpots = await _syncParkingSpots(
      stopId: next.id!,
      previous: previous.parkingSpots,
      next: next.parkingSpots,
    );
    return updatedStop.copyWith(
        parkingSpots: parkingSpots, sortOrder: next.sortOrder);
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
          final updated =
              await _parkingSpotService.updateParkingSpot(parkingSpot);
          return updated.copyWith(sortOrder: parkingSpot.sortOrder);
        } else {
          final created = await _parkingSpotService.createParkingSpot(
            stopId: stopId,
            parkingSpot: parkingSpot.copyWith(id: null),
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
          _parkingSpotService.deleteParkingSpot(removed.id!),
    ]);

    await _parkingSpotService.reorderParkingSpots(
        stopId: stopId, parkingSpots: saved);
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
