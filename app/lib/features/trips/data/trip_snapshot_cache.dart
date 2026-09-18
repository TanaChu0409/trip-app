import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class TripSnapshot {
  const TripSnapshot({
    required this.trips,
    required this.savedAt,
  });

  final List<TripSummary> trips;
  final DateTime savedAt;
}

class TripSnapshotCache {
  TripSnapshotCache._();

  static final TripSnapshotCache instance = TripSnapshotCache._();

  static const int _schemaVersion = 2;
  static const String _keyPrefix = 'trip_snapshot_v2';
  static const int _legacySchemaVersion = 1;
  static const String _legacyKeyPrefix = 'trip_snapshot_v1';

  Future<TripSnapshot?> loadForUser(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final currentSnapshot = _decodeSnapshot(
      preferences.getString(_keyForUser(userId)),
      expectedSchemaVersion: _schemaVersion,
    );
    if (currentSnapshot != null) return currentSnapshot;

    // Version 1 contains active trips only. TripSummary defaults a missing
    // archive flag to false, so its payload is safely compatible with v2.
    final legacySnapshot = _decodeSnapshot(
      preferences.getString(_legacyKeyForUser(userId)),
      expectedSchemaVersion: _legacySchemaVersion,
    );
    if (legacySnapshot == null) return null;

    await saveForUser(
      userId,
      legacySnapshot.trips,
      savedAt: legacySnapshot.savedAt,
    );
    await preferences.remove(_legacyKeyForUser(userId));
    return legacySnapshot;
  }

  TripSnapshot? _decodeSnapshot(
    String? rawSnapshot, {
    required int expectedSchemaVersion,
  }) {
    if (rawSnapshot == null || rawSnapshot.isEmpty) return null;

    try {
      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! Map) {
        return null;
      }

      final json = Map<String, dynamic>.from(decoded);
      if (json['schema_version'] != expectedSchemaVersion) {
        return null;
      }

      final rawSavedAt = json['saved_at'] as String?;
      final savedAt = rawSavedAt == null ? null : DateTime.tryParse(rawSavedAt);
      if (savedAt == null) {
        return null;
      }

      final rawTrips = json['trips'];
      if (rawTrips is! List) {
        return null;
      }

      return TripSnapshot(
        savedAt: savedAt,
        trips: [
          for (final tripJson in rawTrips)
            if (tripJson is Map)
              TripSummary.fromCacheJson(
                Map<String, dynamic>.from(tripJson),
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveForUser(
    String userId,
    List<TripSummary> trips, {
    DateTime? savedAt,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final effectiveSavedAt = savedAt ?? DateTime.now();
    final payload = {
      'schema_version': _schemaVersion,
      'saved_at': effectiveSavedAt.toIso8601String(),
      'trips': [
        for (final trip in trips) trip.toCacheJson(),
      ],
    };

    await preferences.setString(_keyForUser(userId), jsonEncode(payload));
  }

  Future<void> clearForUser(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_keyForUser(userId));
    await preferences.remove(_legacyKeyForUser(userId));
  }

  String _keyForUser(String userId) => '$_keyPrefix:$userId';
  String _legacyKeyForUser(String userId) => '$_legacyKeyPrefix:$userId';
}
