enum TripRole { owner, guest }

enum TripPermission { editor, viewer }

TripPermission tripPermissionFromBackend(String? value) {
  switch (value) {
    case 'editor':
      return TripPermission.editor;
    case 'viewer':
      return TripPermission.viewer;
    default:
      return TripPermission.editor;
  }
}

class ParkingSpot {
  const ParkingSpot({
    this.id,
    required this.name,
    required this.mapUrl,
    this.sortOrder = 0,
  });

  final String? id;

  final String name;
  final String mapUrl;
  final int sortOrder;

  ParkingSpot copyWith({
    String? id,
    String? name,
    String? mapUrl,
    int? sortOrder,
  }) {
    return ParkingSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      mapUrl: mapUrl ?? this.mapUrl,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'map_url': mapUrl,
      'sort_order': sortOrder,
    };
  }

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    return ParkingSpot(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      mapUrl: json['map_url'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class StopItem {
  const StopItem({
    this.id,
    required this.title,
    this.timeLabel,
    this.note,
    this.badge,
    this.mapUrl,
    this.color,
    this.isHighlight = false,
    this.parkingSpots = const [],
    this.sortOrder = 0,
  });

  final String? id;

  final String title;
  final String? timeLabel;
  final String? note;
  final String? badge;
  final String? mapUrl;
  final String? color;
  final bool isHighlight;
  final List<ParkingSpot> parkingSpots;
  final int sortOrder;

  StopItem copyWith({
    String? id,
    String? title,
    String? timeLabel,
    String? note,
    String? badge,
    String? mapUrl,
    String? color,
    bool? isHighlight,
    List<ParkingSpot>? parkingSpots,
    int? sortOrder,
  }) {
    return StopItem(
      id: id ?? this.id,
      title: title ?? this.title,
      timeLabel: timeLabel ?? this.timeLabel,
      note: note ?? this.note,
      badge: badge ?? this.badge,
      mapUrl: mapUrl ?? this.mapUrl,
      color: color ?? this.color,
      isHighlight: isHighlight ?? this.isHighlight,
      parkingSpots: parkingSpots ?? this.parkingSpots,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'time': _normalizeTimeValue(timeLabel),
      'note': note,
      'badge': badge,
      'map_url': mapUrl,
      'color': color,
      'is_highlight': isHighlight,
      'sort_order': sortOrder,
    };
  }

  factory StopItem.fromJson(
    Map<String, dynamic> json, {
    List<ParkingSpot> parkingSpots = const [],
  }) {
    return StopItem(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      timeLabel: _normalizeTimeValue(json['time'] as String?),
      note: json['note'] as String?,
      badge: json['badge'] as String?,
      mapUrl: json['map_url'] as String?,
      color: json['color'] as String?,
      isHighlight: json['is_highlight'] as bool? ?? false,
      parkingSpots: parkingSpots,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class TripDay {
  const TripDay({
    required this.id,
    required this.label,
    required this.dateLabel,
    required this.subtitle,
    required this.stops,
  });

  final String id;
  final String label;
  final String dateLabel;
  final String subtitle;
  final List<StopItem> stops;

  TripDay copyWith({
    String? id,
    String? label,
    String? dateLabel,
    String? subtitle,
    List<StopItem>? stops,
  }) {
    return TripDay(
      id: id ?? this.id,
      label: label ?? this.label,
      dateLabel: dateLabel ?? this.dateLabel,
      subtitle: subtitle ?? this.subtitle,
      stops: stops ?? this.stops,
    );
  }
}

class TripSummary {
  const TripSummary({
    required this.id,
    required this.title,
    required this.dateRange,
    required this.role,
    required this.days,
    this.shareCode,
    this.sharedFromTripId,
    this.color,
    this.permission,
  });

  final String id;
  final String title;
  final String dateRange;
  final TripRole role;
  final List<TripDay> days;
  final String? shareCode;
  final String? sharedFromTripId;
  final String? color;

  /// Permission for guests. `null` when [role] is [TripRole.owner].
  final TripPermission? permission;

  /// Whether the current user may edit this trip's content.
  bool get canEdit =>
      role == TripRole.owner || permission == TripPermission.editor;

  TripSummary copyWith({
    String? id,
    String? title,
    String? dateRange,
    TripRole? role,
    List<TripDay>? days,
    String? shareCode,
    String? sharedFromTripId,
    String? color,
    TripPermission? permission,
  }) {
    return TripSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      dateRange: dateRange ?? this.dateRange,
      role: role ?? this.role,
      days: days ?? this.days,
      shareCode: shareCode ?? this.shareCode,
      sharedFromTripId: sharedFromTripId ?? this.sharedFromTripId,
      color: color ?? this.color,
      permission: permission ?? this.permission,
    );
  }

  int get stopCount => days.fold(0, (sum, day) => sum + day.stops.length);
}

List<StopItem> sortStopsChronologically(Iterable<StopItem> stops) {
  final indexedStops = [
    for (var index = 0; index < stops.length; index += 1)
      _IndexedStop(stop: stops.elementAt(index), index: index),
  ];

  indexedStops.sort((left, right) {
    final leftMinutes = parseTimeLabelToMinutes(left.stop.timeLabel);
    final rightMinutes = parseTimeLabelToMinutes(right.stop.timeLabel);

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

    final sortComparison = left.stop.sortOrder.compareTo(right.stop.sortOrder);
    if (sortComparison != 0) {
      return sortComparison;
    }

    return left.index.compareTo(right.index);
  });

  return [for (final item in indexedStops) item.stop];
}

int? parseTimeLabelToMinutes(String? rawValue) {
  final normalizedValue = _normalizeTimeValue(rawValue);
  if (normalizedValue == null) {
    return null;
  }

  final parts = normalizedValue.split(':');
  if (parts.length != 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }

  return hour * 60 + minute;
}

String? _normalizeTimeValue(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }

  final parts = rawValue.split(':');
  if (parts.length < 2) {
    return rawValue;
  }

  final hour = parts[0].padLeft(2, '0');
  final minute = parts[1].padLeft(2, '0');
  return '$hour:$minute';
}

class _IndexedStop {
  const _IndexedStop({required this.stop, required this.index});

  final StopItem stop;
  final int index;
}
