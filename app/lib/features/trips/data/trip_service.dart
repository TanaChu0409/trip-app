import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trips/data/join_trip_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_member.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class TripService {
  TripService._();

  static final TripService instance = TripService._();

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // Use a cryptographically secure RNG so share codes cannot be predicted
  // by an attacker who knows the approximate generation time.
  final Random _random = Random.secure();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<TripSummary>> fetchTripsForCurrentUser() async {
    final userId = _requireUserId();
    final ownedRows = await _client
        .from('trips')
        .select('id, title, start_date, end_date, share_code, color')
        .eq('owner_id', userId)
        .eq('is_archived', false)
        .order('start_date', ascending: false);

    final sharedAccessRows = await _client
        .from('shared_access')
        .select('trip_id, permission')
        .eq('user_id', userId);

    final permissionByTripId = <String, TripPermission>{
      for (final row in sharedAccessRows)
        row['trip_id'] as String:
            tripPermissionFromBackend(row['permission'] as String?),
    };

    final sharedTripIds = permissionByTripId.keys.toList(growable: false);

    final sharedRows = sharedTripIds.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('trips')
            .select('id, title, start_date, end_date, share_code, color')
            .inFilter('id', sharedTripIds)
            .eq('is_archived', false)
            .order('start_date', ascending: false);

    final ownedTrips =
        await _assembleTrips(rows: ownedRows, role: TripRole.owner);
    final sharedTrips = await _assembleTrips(
      rows: sharedRows,
      role: TripRole.guest,
      permissionByTripId: permissionByTripId,
    );

    return [...ownedTrips, ...sharedTrips];
  }

  Future<TripSummary> createTrip({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? color,
  }) async {
    final userId = _requireUserId();

    for (var attempt = 0; attempt < 5; attempt += 1) {
      final shareCode = _generateShareCode();
      try {
        final tripRow = await _client
            .from('trips')
            .insert({
              'title': title,
              'start_date': _toIsoDate(startDate),
              'end_date': _toIsoDate(endDate),
              'owner_id': userId,
              'share_code': shareCode,
              'color': color,
            })
            .select('id, title, start_date, end_date, share_code, color')
            .single();

        final tripId = tripRow['id'] as String;
        final dayRows = _buildDayRows(
          tripId: tripId,
          startDate: startDate,
          endDate: endDate,
        );

        if (dayRows.isNotEmpty) {
          await _client.from('days').insert(dayRows);
        }

        return (await fetchTripById(tripId, role: TripRole.owner))!;
      } on PostgrestException catch (error) {
        if (error.code != '23505') {
          rethrow;
        }
      }
    }

    throw StateError('Unable to generate a unique share code.');
  }

  Future<TripSummary?> fetchTripById(
    String tripId, {
    TripRole? role,
    TripPermission? permission,
  }) async {
    final rows = await _client
        .from('trips')
        .select('id, title, start_date, end_date, share_code, owner_id, color')
        .eq('id', tripId)
        .limit(1);

    if (rows.isEmpty) {
      return null;
    }

    final row = Map<String, dynamic>.from(rows.first);
    final resolvedRole = role ?? _resolveRole(row);
    final permissionMap = (resolvedRole == TripRole.guest && permission != null)
        ? {tripId: permission}
        : <String, TripPermission>{};
    final trips = await _assembleTrips(
      rows: [row],
      role: resolvedRole,
      permissionByTripId: permissionMap,
    );
    return trips.isEmpty ? null : trips.first;
  }

  Future<JoinTripByCodeResult> joinTripByCode(String rawCode) async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('User must be signed in.');
    }
    final normalizedCode = rawCode.trim().toUpperCase();
    final response = await _client.rpc(
      'join_trip_by_code',
      params: {'p_share_code': normalizedCode},
    );
    if (response is! Map) {
      throw StateError(
        'Expected Map response from join_trip_by_code RPC, but received ${response.runtimeType}: $response',
      );
    }
    final payload = Map<String, dynamic>.from(response);
    final rawStatus = payload['status'];
    if (rawStatus != null && rawStatus is! String) {
      throw StateError(
        'Expected string status from join_trip_by_code RPC, but received: $rawStatus',
      );
    }
    final status = joinTripByCodeStatusFromBackend(rawStatus as String?);
    if (status != JoinTripByCodeStatus.success) {
      return JoinTripByCodeResult(status: status);
    }

    final rawTripId = payload['trip_id'];
    if (rawTripId != null && rawTripId is! String) {
      throw StateError(
        'Expected string trip_id from join_trip_by_code RPC, but received: $rawTripId',
      );
    }
    final tripId = rawTripId as String?;
    if (tripId == null || tripId.isEmpty) {
      throw StateError(
        'Invalid join_trip_by_code RPC response: success status was missing the required trip_id field.',
      );
    }
    final rawPermission = payload['permission'] as String?;
    final permission = tripPermissionFromBackend(rawPermission);
    final trip = await fetchTripById(
      tripId,
      role: TripRole.guest,
      permission: permission,
    );
    if (trip == null) {
      return const JoinTripByCodeResult(
          status: JoinTripByCodeStatus.tripNotFound);
    }

    return JoinTripByCodeResult(
        status: JoinTripByCodeStatus.success, trip: trip);
  }

  Future<bool> deleteOwnedTrip(String tripId) async {
    final userId = _requireUserId();
    final rows = await _client
        .from('trips')
        .delete()
        .eq('id', tripId)
        .eq('owner_id', userId)
        .select('id');
    return rows.isNotEmpty;
  }

  Future<bool> leaveSharedTrip(String tripId) async {
    final userId = _requireUserId();
    final rows = await _client
        .from('shared_access')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', userId)
        .select('trip_id');
    return rows.isNotEmpty;
  }

  Future<void> updateTripColor(String tripId, String? color) async {
    // Calls a SECURITY DEFINER RPC that only updates the color column.
    // A direct table UPDATE is intentionally avoided: the previous
    // trips_editor_update_color RLS policy would have allowed editors to
    // overwrite any field (including owner_id), which the RPC prevents.
    await _client.rpc(
      'update_trip_color',
      params: {'p_trip_id': tripId, 'p_color': color},
    );
  }

  /// Fetch all members (guests) for a trip, joined with their profiles.
  /// Only the trip owner can call this (enforced by RLS on shared_access).
  Future<List<TripMember>> fetchTripMembers(String tripId) async {
    final rows = await _client
        .from('shared_access')
        .select('id, user_id, permission, joined_at')
        .eq('trip_id', tripId);

    if (rows.isEmpty) {
      return const [];
    }

    final userIds = <String>{
      for (final row in rows) (row as Map<String, dynamic>)['user_id'] as String,
    };

    final profileRows = await _client
        .from('profiles_public')
        .select('id, display_name, avatar_url')
        .inFilter('id', userIds.toList(growable: false));

    final profileByUserId = <String, Map<String, dynamic>>{
      for (final row in profileRows)
        (row['id'] as String): Map<String, dynamic>.from(row as Map),
    };

    return [
      for (final row in rows)
        _tripMemberFromSharedAccessRow(
          Map<String, dynamic>.from(row as Map),
          profileByUserId,
        ),
    ];
  }

  /// Update a member's permission. Only the trip owner may call this.
  Future<void> updateMemberPermission(
    String tripId,
    String userId,
    TripPermission permission,
  ) async {
    await _client
        .from('shared_access')
        .update({'permission': permission.name})
        .eq('trip_id', tripId)
        .eq('user_id', userId);
  }

  /// Remove a member from a trip. Only the trip owner may call this.
  Future<void> removeMember(String tripId, String userId) async {
    await _client
        .from('shared_access')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', userId);
  }

  Future<List<TripSummary>> _assembleTrips({
    required List<dynamic> rows,
    required TripRole role,
    Map<String, TripPermission> permissionByTripId = const {},
  }) async {
    if (rows.isEmpty) {
      return const [];
    }

    final tripRows = rows
        .map((row) => Map<String, dynamic>.from(row as Map<String, dynamic>))
        .toList(growable: false);
    final tripIds =
        tripRows.map((row) => row['id'] as String).toList(growable: false);
    final dayRows = await _fetchDays(tripIds);
    final dayIds =
        dayRows.map((row) => row['id'] as String).toList(growable: false);
    final stopRows = await _fetchStops(dayIds);
    final stopIds =
        stopRows.map((row) => row['id'] as String).toList(growable: false);
    final parkingRows = await _fetchParkingSpots(stopIds);

    final parkingByStopId = <String, List<ParkingSpot>>{};
    for (final row in parkingRows) {
      final stopId = row['stop_id'] as String;
      parkingByStopId
          .putIfAbsent(stopId, () => [])
          .add(ParkingSpot.fromJson(row));
    }

    final stopsByDayId = <String, List<StopItem>>{};
    for (final row in stopRows) {
      final dayId = row['day_id'] as String;
      final stopId = row['id'] as String;
      stopsByDayId.putIfAbsent(dayId, () => []).add(
            StopItem.fromJson(
              row,
              parkingSpots: parkingByStopId[stopId] ?? const [],
            ),
          );
    }

    final daysByTripId = <String, List<TripDay>>{};
    for (final row in dayRows) {
      final tripId = row['trip_id'] as String;
      final date = DateTime.parse(row['date'] as String);
      daysByTripId.putIfAbsent(tripId, () => []).add(
            TripDay(
              id: row['id'] as String,
              label: row['label'] as String? ?? '',
              dateLabel: '${date.month}/${date.day}',
              subtitle: row['subtitle'] as String? ?? '',
              stops: stopsByDayId[row['id'] as String] ?? const [],
            ),
          );
    }

    return tripRows
        .map(
          (row) => TripSummary(
            id: row['id'] as String,
            title: row['title'] as String? ?? '',
            dateRange: _formatRange(
              DateTime.parse(row['start_date'] as String),
              DateTime.parse(row['end_date'] as String),
            ),
            role: role,
            days: daysByTripId[row['id'] as String] ?? const [],
            shareCode: row['share_code'] as String?,
            color: row['color'] as String?,
            permission: permissionByTripId[row['id'] as String],
          ),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchDays(List<String> tripIds) async {
    if (tripIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('days')
        .select('id, trip_id, date, label, subtitle, sort_order')
        .inFilter('trip_id', tripIds)
        .order('sort_order', ascending: true);
    // The database already returns rows sorted by sort_order; no local
    // re-sort is needed.
    final result = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return List<Map<String, dynamic>>.unmodifiable(result);
  }

  Future<List<Map<String, dynamic>>> _fetchStops(List<String> dayIds) async {
    if (dayIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('stops')
        .select(
            'id, day_id, time, title, note, badge, map_url, color, is_highlight, sort_order')
        .inFilter('day_id', dayIds)
        .order('sort_order');
    final result = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: true);
    result.sort((left, right) {
      final dayComparison =
          (left['day_id'] as String).compareTo(right['day_id'] as String);
      if (dayComparison != 0) {
        return dayComparison;
      }

      final leftMinutes = parseTimeLabelToMinutes(left['time'] as String?);
      final rightMinutes = parseTimeLabelToMinutes(right['time'] as String?);
      if (leftMinutes == null && rightMinutes != null) {
        return 1;
      }
      if (leftMinutes != null && rightMinutes == null) {
        return -1;
      }
      if (leftMinutes != null && rightMinutes != null) {
        final timeComparison = leftMinutes.compareTo(rightMinutes);
        if (timeComparison != 0) {
          return timeComparison;
        }
      }

      final leftSortOrder = left['sort_order'] as int? ?? 0;
      final rightSortOrder = right['sort_order'] as int? ?? 0;
      return leftSortOrder.compareTo(rightSortOrder);
    });
    return List<Map<String, dynamic>>.unmodifiable(result);
  }

  Future<List<Map<String, dynamic>>> _fetchParkingSpots(
      List<String> stopIds) async {
    if (stopIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('parking_spots')
        .select('id, stop_id, name, map_url, sort_order')
        .inFilter('stop_id', stopIds)
        .order('sort_order');
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _buildDayRows({
    required String tripId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final rows = <Map<String, dynamic>>[];
    var current = DateTime(startDate.year, startDate.month, startDate.day);
    final last = DateTime(endDate.year, endDate.month, endDate.day);
    var index = 0;

    while (!current.isAfter(last)) {
      index += 1;
      rows.add({
        'trip_id': tripId,
        'date': _toIsoDate(current),
        'label': '第${_toChineseNumber(index)}天',
        'subtitle': index == 1 ? '從這一天開始安排行程。' : '這一天的詳細行程尚未建立。',
        'sort_order': index - 1,
      });
      current = current.add(const Duration(days: 1));
    }

    return rows;
  }

  TripRole _resolveRole(Map<String, dynamic> row) {
    final userId = _requireUserId();
    return row['owner_id'] == userId ? TripRole.owner : TripRole.guest;
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User must be signed in.');
    }
    return userId;
  }

  String _generateShareCode() {
    // 8 characters from a 32-symbol alphabet gives ~1 trillion combinations
    // (~32^8), making brute-force enumeration infeasible even without rate
    // limiting. Combined with the server-side rate limit (migration 014) this
    // provides defence-in-depth.
    final buffer = StringBuffer();
    for (var index = 0; index < 8; index += 1) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  String _toIsoDate(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String().split('T').first;
  }

  String _formatRange(DateTime startDate, DateTime endDate) {
    String format(DateTime value) {
      final month = value.month.toString().padLeft(2, '0');
      final day = value.day.toString().padLeft(2, '0');
      return '${value.year}/$month/$day';
    }

    return '${format(startDate)} - ${format(endDate)}';
  }

  String _toChineseNumber(int value) {
    const labels = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (value >= 0 && value < labels.length) {
      return labels[value];
    }
    return value.toString();
  }

  TripMember _tripMemberFromSharedAccessRow(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> profileByUserId,
  ) {
    row['profiles'] =
        profileByUserId[row['user_id'] as String] ??
        const <String, dynamic>{};
    return TripMember.fromJson(row);
  }
}
