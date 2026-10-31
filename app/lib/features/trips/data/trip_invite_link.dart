import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

enum TripInviteStatus {
  success,
  alreadyMember,
  owner,
  invalidLink,
  tripArchived,
  notOwner,
  invalidPermission,
}

class TripInviteLinkResult {
  const TripInviteLinkResult(
      {required this.status,
      this.tripId,
      this.title,
      this.permission,
      this.token,
      this.active = false});

  final TripInviteStatus status;
  final String? tripId;
  final String? title;
  final TripPermission? permission;
  final String? token;
  final bool active;

  factory TripInviteLinkResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'success' => TripInviteStatus.success,
      'already_member' => TripInviteStatus.alreadyMember,
      'owner' => TripInviteStatus.owner,
      'invalid_link' => TripInviteStatus.invalidLink,
      'trip_archived' => TripInviteStatus.tripArchived,
      'not_owner' => TripInviteStatus.notOwner,
      'invalid_permission' => TripInviteStatus.invalidPermission,
      _ => throw const FormatException('Unknown invitation response'),
    };
    final rawPermission = json['permission'];
    if (rawPermission != null &&
        rawPermission != 'editor' &&
        rawPermission != 'viewer') {
      throw const FormatException('Invalid invitation permission');
    }
    return TripInviteLinkResult(
        status: status,
        tripId: json['trip_id'] as String?,
        title: json['title'] as String?,
        token: json['token'] as String?,
        active: json['active'] as bool? ?? false,
        permission: rawPermission == null
            ? null
            : tripPermissionFromBackend(rawPermission as String));
  }
}
