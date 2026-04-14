import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/config/supabase_options.dart';
import 'package:trip_planner_app/features/notifications/services/notification_service.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:uuid/uuid.dart';

class TripStoreException implements Exception {
  const TripStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TripStore extends ChangeNotifier {
  TripStore._() {
    _restoreDemoTrips();
  }

  static final TripStore instance = TripStore._();

  final Uuid _uuid = const Uuid();
  final List<TripSummary> _trips = [];

  bool _initialized = false;
  bool _isLoading = false;
  bool _isRemoteActive = false;
  String? _statusMessage;

  List<TripSummary> get trips => List<TripSummary>.unmodifiable(_trips);
  bool get isLoading => _isLoading;
  bool get isRemoteActive => _isRemoteActive;
  String? get statusMessage => _statusMessage;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!SupabaseOptions.isConfigured) {
      _statusMessage = '尚未設定 Supabase，現在使用示範資料。';
      notifyListeners();
      return;
    }

    await refresh();
  }

  Future<void> refresh() async {
    if (!SupabaseOptions.isConfigured) {
      return;
    }

    await _runWithLoading(() async {
      try {
        await _ensureAuthenticated();
        await _reloadFromSupabase();
        _isRemoteActive = true;
        _statusMessage = 'Supabase 已連線，旅程資料會即時同步。';
      } catch (_) {
        _restoreDemoTrips();
        _isRemoteActive = false;
        _statusMessage = 'Supabase 連線失敗，已切回示範資料。';
      }
    });
  }

  TripSummary? findById(String id) {
    for (final trip in _trips) {
      if (trip.id == id) {
        return trip;
      }
    }
    return null;
  }

  Future<TripSummary> createTrip({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final normalizedStart = _normalizeDate(startDate);
    final normalizedEnd = _normalizeDate(endDate);

    if (!_isRemoteActive) {
      final trip = _createLocalTrip(
        title: title,
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );
      notifyListeners();
      return trip;
    }

    return _runWithLoading(() async {
      await _ensureAuthenticated();

      final tripRow =
          await _client.from('trips').insert({
            'title': title,
            'start_date': _toIsoDate(normalizedStart),
            'end_date': _toIsoDate(normalizedEnd),
            'owner_id': _currentUserId,
            'share_code': _buildShareCode(),
          }).select('id').single();

      final tripId = tripRow['id'] as String;
      final dayRows = _buildDayPayload(
        tripId: tripId,
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );

      if (dayRows.isNotEmpty) {
        await _client.from('days').insert(dayRows);
      }

      await _reloadFromSupabase();
      return findById(tripId) ??
          _throwStoreException('建立旅程後同步失敗，請重新整理後再試。');
    });
  }

  Future<TripSummary> updateTrip({
    required String tripId,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final trip = findById(tripId);
    if (trip == null || trip.role != TripRole.owner) {
      throw const TripStoreException('找不到可編輯的旅程。');
    }

    final normalizedStart = _normalizeDate(startDate);
    final normalizedEnd = _normalizeDate(endDate);

    if (!_isRemoteActive) {
      final updatedTrip = _updateLocalTrip(
        trip: trip,
        title: title,
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );
      notifyListeners();
      return updatedTrip;
    }

    return _runWithLoading(() async {
      await _ensureAuthenticated();

      await _client.from('trips').update({
        'title': title,
        'start_date': _toIsoDate(normalizedStart),
        'end_date': _toIsoDate(normalizedEnd),
      }).eq('id', tripId);

      final existingByDate = <String, TripDay>{
        for (final day in trip.days)
          if (day.date != null) _dateKey(day.date!): day,
      };
      final targetDates = _expandDates(normalizedStart, normalizedEnd);
      final targetKeys = targetDates.map(_dateKey).toSet();
      final removedDayIds = [
        for (final day in trip.days)
          if (day.date != null && !targetKeys.contains(_dateKey(day.date!))) day.id,
      ];

      for (var index = 0; index < targetDates.length; index += 1) {
        final date = targetDates[index];
        final key = _dateKey(date);
        final existingDay = existingByDate[key];
        final payload = {
          'trip_id': tripId,
          'date': _toIsoDate(date),
          'label': _buildDayLabel(index + 1),
          'subtitle': existingDay?.subtitle ??
              (index == 0 ? '從這一天開始安排行程。' : '這一天的詳細行程尚未建立。'),
          'sort_order': index,
        };

        if (existingDay == null) {
          await _client.from('days').insert(payload);
        } else {
          await _client.from('days').update(payload).eq('id', existingDay.id);
        }
      }

      if (removedDayIds.isNotEmpty) {
        await _client.from('days').delete().inFilter('id', removedDayIds);
      }

      await _reloadFromSupabase();
      return findById(tripId) ??
          _throwStoreException('更新旅程後同步失敗，請重新整理後再試。');
    });
  }

  Future<bool> deleteTrip(String tripId) async {
    final trip = findById(tripId);
    if (trip == null || trip.role != TripRole.owner) {
      return false;
    }

    if (!_isRemoteActive) {
      _trips.removeWhere((item) => item.id == tripId);
      await NotificationService.instance.cancelTripReminders(tripId);
      notifyListeners();
      return true;
    }

    return _runWithLoading(() async {
      await _ensureAuthenticated();
      await _client.from('trips').delete().eq('id', tripId);
      await _reloadFromSupabase();
      return true;
    });
  }

  Future<bool> leaveSharedTrip(String tripId) async {
    final trip = findById(tripId);
    if (trip == null || trip.role != TripRole.guest) {
      return false;
    }

    if (!_isRemoteActive) {
      _trips.removeWhere((item) => item.id == tripId);
      await NotificationService.instance.cancelTripReminders(tripId);
      notifyListeners();
      return true;
    }

    return _runWithLoading(() async {
      await _ensureAuthenticated();
      await _client
          .from('shared_access')
          .delete()
          .eq('trip_id', tripId)
          .eq('user_id', _currentUserId);
      await _reloadFromSupabase();
      return true;
    });
  }

  Future<bool> joinTrip(String shareCode) async {
    final normalizedCode = shareCode.trim().toUpperCase();
    if (normalizedCode.length != 6 || !_isRemoteActive) {
      return false;
    }

    return _runWithLoading(() async {
      await _ensureAuthenticated();
      await _client.rpc(
        'join_trip_by_share_code',
        params: {'input_share_code': normalizedCode},
      );
      await _reloadFromSupabase();
      return true;
    });
  }

  void resetForTests() {
    _initialized = false;
    _statusMessage = null;
    _isRemoteActive = false;
    _isLoading = false;
    _restoreDemoTrips();
    notifyListeners();
  }

  Future<T> _runWithLoading<T>(Future<T> Function() action) async {
    _isLoading = true;
    notifyListeners();

    try {
      return await action();
    } on PostgrestException catch (error) {
      throw TripStoreException(error.message);
    } on AuthException catch (error) {
      throw TripStoreException(error.message);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  String get _currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const TripStoreException('尚未建立登入 session。');
    }
    return userId;
  }

  Future<void> _ensureAuthenticated() async {
    if (_client.auth.currentSession != null) {
      return;
    }
    await _client.auth.signInAnonymously();
  }

  Future<void> _reloadFromSupabase() async {
    final ownedRows = await _client
        .from('trips')
        .select('id, title, start_date, end_date, owner_id, share_code')
        .eq('owner_id', _currentUserId)
        .eq('is_archived', false)
        .order('start_date');

    final sharedAccessRows = await _client
        .from('shared_access')
        .select('trip_id')
        .eq('user_id', _currentUserId);

    final sharedTripIds = [
      for (final row in sharedAccessRows as List<dynamic>) row['trip_id'] as String,
    ];

    final sharedRows = sharedTripIds.isEmpty
        ? <dynamic>[]
        : await _client
            .from('trips')
            .select('id, title, start_date, end_date, owner_id, share_code')
            .inFilter('id', sharedTripIds)
            .eq('is_archived', false)
            .order('start_date');

    final ownerTrips = _mapTripRows(ownedRows as List<dynamic>, TripRole.owner);
    final guestTrips = _mapTripRows(sharedRows as List<dynamic>, TripRole.guest);
    final allTrips = [...ownerTrips, ...guestTrips];
    final tripIds = allTrips.map((trip) => trip.id).toList();

    final dayRows = tripIds.isEmpty
        ? <dynamic>[]
        : await _client
            .from('days')
            .select('id, trip_id, date, label, subtitle, sort_order')
            .inFilter('trip_id', tripIds)
            .order('sort_order')
            .order('date');

    final dayIds = [
      for (final row in dayRows as List<dynamic>) row['id'] as String,
    ];

    final stopRows = dayIds.isEmpty
        ? <dynamic>[]
        : await _client
            .from('stops')
            .select(
              'id, day_id, time, title, note, badge, map_url, is_highlight, sort_order',
            )
            .inFilter('day_id', dayIds)
            .order('sort_order');

    final stopIds = [
      for (final row in stopRows as List<dynamic>) row['id'] as String,
    ];

    final parkingRows = stopIds.isEmpty
        ? <dynamic>[]
        : await _client
            .from('parking_spots')
            .select('id, stop_id, name, map_url, sort_order')
            .inFilter('stop_id', stopIds)
            .order('sort_order');

    final trips = _hydrateTrips(
      trips: allTrips,
      dayRows: dayRows,
      stopRows: stopRows,
      parkingRows: parkingRows,
    );

    _trips
      ..clear()
      ..addAll(trips);
    await _reseedNotifications();
  }

  List<TripSummary> _mapTripRows(List<dynamic> rows, TripRole role) {
    return [
      for (final dynamic row in rows)
        TripSummary(
          id: row['id'] as String,
          title: row['title'] as String? ?? '未命名旅程',
          role: role,
          startDate: DateTime.parse(row['start_date'] as String),
          endDate: DateTime.parse(row['end_date'] as String),
          shareCode: row['share_code'] as String?,
          ownerId: row['owner_id'] as String?,
          days: const [],
        ),
    ];
  }

  List<TripSummary> _hydrateTrips({
    required List<TripSummary> trips,
    required List<dynamic> dayRows,
    required List<dynamic> stopRows,
    required List<dynamic> parkingRows,
  }) {
    final parkingByStop = <String, List<ParkingSpot>>{};
    for (final dynamic row in parkingRows) {
      final stopId = row['stop_id'] as String;
      parkingByStop.putIfAbsent(stopId, () => []).add(
            ParkingSpot(
              id: row['id'] as String?,
              name: row['name'] as String,
              mapUrl: row['map_url'] as String,
            ),
          );
    }

    final stopsByDay = <String, List<StopItem>>{};
    for (final dynamic row in stopRows) {
      final stopId = row['id'] as String;
      final dayId = row['day_id'] as String;
      stopsByDay.putIfAbsent(dayId, () => []).add(
            StopItem(
              id: stopId,
              title: row['title'] as String,
              timeLabel: _formatTimeLabel(row['time']),
              note: row['note'] as String?,
              badge: row['badge'] as String?,
              mapUrl: row['map_url'] as String?,
              isHighlight: row['is_highlight'] as bool? ?? false,
              parkingSpots: parkingByStop[stopId] ?? const [],
            ),
          );
    }

    final daysByTrip = <String, List<TripDay>>{};
    for (final dynamic row in dayRows) {
      final tripId = row['trip_id'] as String;
      final date = DateTime.parse(row['date'] as String);
      daysByTrip.putIfAbsent(tripId, () => []).add(
            TripDay(
              id: row['id'] as String,
              label: row['label'] as String,
              dateLabel: _buildDateLabel(date),
              subtitle: row['subtitle'] as String? ?? '這一天的詳細行程尚未建立。',
              stops: stopsByDay[row['id'] as String] ?? const [],
              date: date,
            ),
          );
    }

    return [
      for (final trip in trips)
        trip.copyWith(
          days: (daysByTrip[trip.id]?.isNotEmpty ?? false)
              ? daysByTrip[trip.id]
              : (trip.startDate != null && trip.endDate != null
                  ? _buildLocalDays(
                      tripId: trip.id,
                      startDate: trip.startDate!,
                      endDate: trip.endDate!,
                    )
                  : const []),
          dateRange: trip.startDate != null && trip.endDate != null
              ? formatDateRange(trip.startDate!, trip.endDate!)
              : trip.dateRange,
        ),
    ];
  }

  TripSummary _createLocalTrip({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final tripId = _slugify(title, DateTime.now().millisecondsSinceEpoch);
    final trip = TripSummary(
      id: tripId,
      title: title,
      role: TripRole.owner,
      startDate: startDate,
      endDate: endDate,
      shareCode: _buildShareCode(),
      days: _buildLocalDays(
        tripId: tripId,
        startDate: startDate,
        endDate: endDate,
      ),
    );

    _trips.insert(0, trip);
    unawaited(NotificationService.instance.scheduleTripReminders(trip));
    return trip;
  }

  TripSummary _updateLocalTrip({
    required TripSummary trip,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final existingByDate = <String, TripDay>{
      for (final day in trip.days)
        if (day.date != null) _dateKey(day.date!): day,
    };
    final updatedTrip = trip.copyWith(
      title: title,
      startDate: startDate,
      endDate: endDate,
      days: _buildLocalDays(
        tripId: trip.id,
        startDate: startDate,
        endDate: endDate,
        existingByDate: existingByDate,
      ),
    );

    final index = _trips.indexWhere((item) => item.id == trip.id);
    _trips[index] = updatedTrip;
    unawaited(NotificationService.instance.scheduleTripReminders(updatedTrip));
    return updatedTrip;
  }

  List<Map<String, dynamic>> _buildDayPayload({
    required String tripId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final dates = _expandDates(startDate, endDate);
    return [
      for (var index = 0; index < dates.length; index += 1)
        {
          'trip_id': tripId,
          'date': _toIsoDate(dates[index]),
          'label': _buildDayLabel(index + 1),
          'subtitle': index == 0 ? '從這一天開始安排行程。' : '這一天的詳細行程尚未建立。',
          'sort_order': index,
        },
    ];
  }

  List<TripDay> _buildLocalDays({
    required String tripId,
    required DateTime startDate,
    required DateTime endDate,
    Map<String, TripDay>? existingByDate,
  }) {
    final dates = _expandDates(startDate, endDate);
    return [
      for (var index = 0; index < dates.length; index += 1)
        _buildLocalDay(
          tripId: tripId,
          date: dates[index],
          index: index,
          existingDay: existingByDate?[_dateKey(dates[index])],
        ),
    ];
  }

  TripDay _buildLocalDay({
    required String tripId,
    required DateTime date,
    required int index,
    TripDay? existingDay,
  }) {
    return TripDay(
      id: existingDay?.id ?? '$tripId-day${index + 1}',
      label: _buildDayLabel(index + 1),
      dateLabel: _buildDateLabel(date),
      subtitle: existingDay?.subtitle ??
          (index == 0 ? '從這一天開始安排行程。' : '這一天的詳細行程尚未建立。'),
      stops: existingDay?.stops ?? const [],
      date: date,
    );
  }

  void _restoreDemoTrips() {
    _trips
      ..clear()
      ..addAll(demoTrips);
    unawaited(_reseedNotifications());
  }

  Future<void> _reseedNotifications() async {
    NotificationService.instance.clearAllReminders();
    await Future.wait(
      [
        for (final trip in _trips) NotificationService.instance.scheduleTripReminders(trip),
      ],
    );
  }

  List<DateTime> _expandDates(DateTime startDate, DateTime endDate) {
    final values = <DateTime>[];
    var cursor = startDate;

    while (!cursor.isAfter(endDate)) {
      values.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return values;
  }

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _toIsoDate(DateTime value) {
    final normalized = _normalizeDate(value);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  String _buildDateLabel(DateTime value) {
    const weekdays = {
      DateTime.monday: '週一',
      DateTime.tuesday: '週二',
      DateTime.wednesday: '週三',
      DateTime.thursday: '週四',
      DateTime.friday: '週五',
      DateTime.saturday: '週六',
      DateTime.sunday: '週日',
    };
    final weekdayLabel = weekdays[value.weekday] ?? '週?';
    return '${value.month}/${value.day} $weekdayLabel';
  }

  String _buildDayLabel(int value) {
    const labels = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (value > 0 && value <= labels.length) {
      return '第${labels[value - 1]}天';
    }
    return '第${value}天';
  }

  String _buildShareCode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 6).toUpperCase();
  }

  String _dateKey(DateTime value) => _toIsoDate(value);

  String _slugify(String input, int timestamp) {
    final normalized = input.trim().replaceAll(RegExp(r'\s+'), '-');
    final ascii = normalized.replaceAll(RegExp(r'[^\w\-\u4e00-\u9fff]'), '');
    return '${ascii.isEmpty ? 'trip' : ascii}-$timestamp';
  }

  String? _formatTimeLabel(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  Never _throwStoreException(String message) {
    throw TripStoreException(message);
  }
}
