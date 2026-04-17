import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class TripMember {
  const TripMember({
    required this.id,
    required this.userId,
    required this.displayName,
    this.email,
    this.avatarUrl,
    required this.permission,
    required this.joinedAt,
  });

  /// `shared_access.id`
  final String id;
  final String userId;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final TripPermission permission;
  final DateTime joinedAt;

  TripMember copyWith({
    String? id,
    String? userId,
    String? displayName,
    String? email,
    String? avatarUrl,
    TripPermission? permission,
    DateTime? joinedAt,
  }) {
    return TripMember(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      permission: permission ?? this.permission,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  factory TripMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return TripMember(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: profile?['display_name'] as String? ??
          profile?['email'] as String? ??
          '未知使用者',
      email: profile?['email'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      permission:
          tripPermissionFromBackend(json['permission'] as String?),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}
