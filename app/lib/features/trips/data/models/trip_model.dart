enum TripRole { owner, guest }

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
  });

  final String id;
  final String title;
  final String dateRange;
  final TripRole role;
  final List<TripDay> days;
  final String? shareCode;
  final String? sharedFromTripId;

  TripSummary copyWith({
    String? id,
    String? title,
    String? dateRange,
    TripRole? role,
    List<TripDay>? days,
    String? shareCode,
    String? sharedFromTripId,
  }) {
    return TripSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      dateRange: dateRange ?? this.dateRange,
      role: role ?? this.role,
      days: days ?? this.days,
      shareCode: shareCode ?? this.shareCode,
      sharedFromTripId: sharedFromTripId ?? this.sharedFromTripId,
    );
  }

  int get stopCount => days.fold(0, (sum, day) => sum + day.stops.length);
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
