import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  test('stop item json roundtrip preserves fields', () {
    const stop = StopItem(
      id: 'stop-1',
      title: '嘉義站',
      timeLabel: '9:5',
      note: '測試備註',
      badge: '午餐',
      mapUrl: 'https://example.com',
      color: '#F97316',
      isHighlight: true,
      sortOrder: 2,
    );

    final restored = StopItem.fromJson(stop.toJson());

    expect(restored.id, 'stop-1');
    expect(restored.title, '嘉義站');
    expect(restored.timeLabel, '09:05');
    expect(restored.note, '測試備註');
    expect(restored.badge, '午餐');
    expect(restored.mapUrl, 'https://example.com');
    expect(restored.color, '#F97316');
    expect(restored.isHighlight, isTrue);
    expect(restored.sortOrder, 2);
  });

  test('trip summary copyWith preserves and overrides color', () {
    const trip = TripSummary(
      id: 'trip-1',
      title: '測試旅程',
      dateRange: '2026/05/01 - 2026/05/02',
      role: TripRole.owner,
      days: [],
      color: '#003D79',
    );

    final updated = trip.copyWith(color: '#F97316');

    expect(updated.color, '#F97316');
    expect(updated.title, '測試旅程');
  });

  test('trip summary stop count aggregates nested stops', () {
    const trip = TripSummary(
      id: 'trip-1',
      title: '測試旅程',
      dateRange: '2026/05/01 - 2026/05/02',
      role: TripRole.owner,
      days: [
        TripDay(
          id: 'day-1',
          label: '第一天',
          dateLabel: '5/1',
          subtitle: '說明',
          stops: [
            StopItem(title: 'A'),
            StopItem(title: 'B'),
          ],
        ),
        TripDay(
          id: 'day-2',
          label: '第二天',
          dateLabel: '5/2',
          subtitle: '說明',
          stops: [StopItem(title: 'C')],
        ),
      ],
    );

    expect(trip.stopCount, 3);
  });

  test('sort stops chronologically with untimed stops last', () {
    const stops = [
      StopItem(title: '午餐', timeLabel: '12:00', sortOrder: 1),
      StopItem(title: '未排定', sortOrder: 0),
      StopItem(title: '早餐', timeLabel: '08:30', sortOrder: 2),
    ];

    final sorted = sortStopsChronologically(stops);

    expect(sorted.map((stop) => stop.title).toList(), ['早餐', '午餐', '未排定']);
  });

  test('sort stops keeps sort order for matching times', () {
    const stops = [
      StopItem(title: 'B 點', timeLabel: '09:00', sortOrder: 1),
      StopItem(title: 'A 點', timeLabel: '09:00', sortOrder: 0),
      StopItem(title: 'C 點', timeLabel: '09:00', sortOrder: 2),
    ];

    final sorted = sortStopsChronologically(stops);

    expect(sorted.map((stop) => stop.title).toList(), ['A 點', 'B 點', 'C 點']);
  });

  group('TripSummary.canEdit', () {
    test('owner can always edit', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.owner,
        days: [],
      );
      expect(trip.canEdit, isTrue);
    });

    test('guest with editor permission can edit', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.guest,
        days: [],
        permission: TripPermission.editor,
      );
      expect(trip.canEdit, isTrue);
    });

    test('guest with viewer permission cannot edit', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.guest,
        days: [],
        permission: TripPermission.viewer,
      );
      expect(trip.canEdit, isFalse);
    });

    test('guest with null permission cannot edit', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.guest,
        days: [],
      );
      expect(trip.canEdit, isFalse);
    });
  });

  group('TripSummary.isReadOnly', () {
    test('owner is not read-only', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.owner,
        days: [],
      );
      expect(trip.isReadOnly, isFalse);
    });

    test('guest editor is not read-only', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.guest,
        days: [],
        permission: TripPermission.editor,
      );
      expect(trip.isReadOnly, isFalse);
    });

    test('guest viewer is read-only', () {
      const trip = TripSummary(
        id: 't',
        title: 't',
        dateRange: '2026/01/01 - 2026/01/02',
        role: TripRole.guest,
        days: [],
        permission: TripPermission.viewer,
      );
      expect(trip.isReadOnly, isTrue);
    });
  });

  group('StopPhoto', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'id': 'photo-1',
        'stop_id': 'stop-1',
        'storage_path': 'user-1/trip-1/stop-1/abc.jpg',
        'sort_order': 2,
      };

      final photo = StopPhoto.fromJson(
        json,
        publicUrl: 'https://cdn.example.com/stop-photos/user-1/trip-1/stop-1/abc.jpg',
      );

      expect(photo.id, 'photo-1');
      expect(photo.storagePath, 'user-1/trip-1/stop-1/abc.jpg');
      expect(photo.url, 'https://cdn.example.com/stop-photos/user-1/trip-1/stop-1/abc.jpg');
      expect(photo.sortOrder, 2);
    });

    test('fromJson uses defaults for missing fields', () {
      final photo = StopPhoto.fromJson(
        const <String, dynamic>{},
        publicUrl: 'https://cdn.example.com/test.jpg',
      );

      expect(photo.id, isNull);
      expect(photo.storagePath, '');
      expect(photo.sortOrder, 0);
    });

    test('copyWith overrides only specified fields', () {
      const original = StopPhoto(
        id: 'photo-1',
        storagePath: 'path/a.jpg',
        url: 'https://cdn.example.com/a.jpg',
        sortOrder: 0,
      );

      final updated = original.copyWith(sortOrder: 3);

      expect(updated.id, 'photo-1');
      expect(updated.storagePath, 'path/a.jpg');
      expect(updated.sortOrder, 3);
    });
  });

  group('StopItem.photos', () {
    test('photos defaults to empty list', () {
      const stop = StopItem(title: '地點');
      expect(stop.photos, isEmpty);
    });

    test('fromJson with photos parameter attaches photos', () {
      const photos = [
        StopPhoto(
          id: 'p1',
          storagePath: 'user/trip/stop/p1.jpg',
          url: 'https://cdn.example.com/p1.jpg',
        ),
      ];

      final stop = StopItem.fromJson(
        {'id': 'stop-1', 'title': '測試地點'},
        photos: photos,
      );

      expect(stop.photos.length, 1);
      expect(stop.photos.first.id, 'p1');
    });

    test('copyWith with photos replaces photo list', () {
      const original = StopItem(title: '地點');

      final updated = original.copyWith(
        photos: const [
          StopPhoto(
            id: 'p1',
            storagePath: 'path.jpg',
            url: 'https://cdn.example.com/path.jpg',
          ),
        ],
      );

      expect(original.photos, isEmpty);
      expect(updated.photos.length, 1);
    });

    test('toJson does not include photos field', () {
      const stop = StopItem(
        id: 'stop-1',
        title: '地點',
        photos: [
          StopPhoto(
            id: 'p1',
            storagePath: 'path.jpg',
            url: 'https://cdn.example.com/path.jpg',
          ),
        ],
      );

      final json = stop.toJson();

      expect(json.containsKey('photos'), isFalse);
      expect(json['id'], 'stop-1');
      expect(json['title'], '地點');
    });
  });
}
