import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trips/data/models/profile_model.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(Supabase.instance.client);
});

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  /// Fetch multiple profiles in one query.
  Future<List<Profile>> fetchProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return const [];
    final rows = await _client
        .from('profiles')
        .select('id, display_name, email, avatar_url')
        .inFilter('id', userIds);
    return [
      for (final row in rows) Profile.fromJson(row),
    ];
  }

  /// Ensure the current user has a profile row (idempotent upsert).
  /// Call this after a successful sign-in.
  Future<void> upsertCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata ?? {};
    await _client.from('profiles').upsert({
      'id': user.id,
      'display_name': meta['full_name'] ?? meta['name'],
      'email': user.email,
      'avatar_url': meta['avatar_url'],
    });
  }
}
