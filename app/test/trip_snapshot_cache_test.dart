import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_snapshot_cache.dart';

void main() {
  late TripSnapshotCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cache = TripSnapshotCache.instance;
  });

  test('saves and loads trip snapshots for a user', () async {
    final trip = TripSummary(
      id: 'trip-1',
      title: '台南兩天一夜',
      dateRange: '2026/05/01 - 2026/05/02',
      role: TripRole.owner,
      shareCode: 'ABCD12',
      color: '#0F766E',
      days: [
        TripDay(
          id: 'day-1',
          label: '第一天',
          dateLabel: '5/1',
          subtitle: '出發',
          stops: [
            StopItem(
              id: 'stop-1',
              title: '早餐',
              timeLabel: '8:5',
              note: '先吃飽',
              badge: '食物',
              mapUrl: 'https://example.com',
              color: '#F97316',
              isHighlight: true,
              parkingSpots: [
                const ParkingSpot(
                  id: 'parking-1',
                  name: '停車場',
                  mapUrl: 'https://example.com/parking',
                  sortOrder: 1,
                ),
              ],
              photos: [
                StopPhoto(
                  id: 'photo-1',
                  storagePath: 'user/trip/stop/photo.jpg',
                  url: 'https://cdn.example.com/photo.jpg',
                  signedUrlExpiresAt: DateTime.utc(2026, 1, 1, 12),
                  sortOrder: 2,
                ),
              ],
              sortOrder: 3,
            ),
          ],
        ),
      ],
    );

    await cache.saveForUser(
      'user-1',
      [trip],
      savedAt: DateTime.utc(2026, 6, 1, 8),
    );

    final snapshot = await cache.loadForUser('user-1');

    expect(snapshot, isNotNull);
    expect(snapshot!.savedAt, DateTime.utc(2026, 6, 1, 8));
    expect(snapshot.trips.single.title, '台南兩天一夜');
    expect(snapshot.trips.single.days.single.stops.single.timeLabel, '08:05');
    expect(
      snapshot.trips.single.days.single.stops.single.photos.single.storagePath,
      'user/trip/stop/photo.jpg',
    );
  });

  test('keeps snapshots separated by user id', () async {
    const userOneTrip = TripSummary(
      id: 'trip-1',
      title: 'User one',
      dateRange: '2026/05/01 - 2026/05/02',
      role: TripRole.owner,
      days: [],
    );
    const userTwoTrip = TripSummary(
      id: 'trip-2',
      title: 'User two',
      dateRange: '2026/05/03 - 2026/05/04',
      role: TripRole.guest,
      permission: TripPermission.viewer,
      days: [],
    );

    await cache.saveForUser('user-1', const [userOneTrip]);
    await cache.saveForUser('user-2', const [userTwoTrip]);

    expect((await cache.loadForUser('user-1'))!.trips.single.title, 'User one');
    expect((await cache.loadForUser('user-2'))!.trips.single.title, 'User two');
  });

  test('ignores corrupt snapshot payloads', () async {
    SharedPreferences.setMockInitialValues({
      'trip_snapshot_v1:user-1': '{not-json',
    });

    expect(await cache.loadForUser('user-1'), isNull);
  });

  test('ignores snapshots with invalid trip roles', () async {
    SharedPreferences.setMockInitialValues({
      'trip_snapshot_v1:user-1': jsonEncode({
        'schema_version': 1,
        'saved_at': DateTime.utc(2026, 6, 1, 8).toIso8601String(),
        'trips': [
          {
            'id': 'trip-1',
            'title': 'Bad role',
            'date_range': '2026/05/01 - 2026/05/02',
            'role': 'admin',
            'days': [],
          },
        ],
      }),
    });

    expect(await cache.loadForUser('user-1'), isNull);
  });
}
