class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final String? displayName;
  final String? email;
  final String? avatarUrl;

  String get effectiveName =>
      displayName?.isNotEmpty == true
          ? displayName!
          : email?.isNotEmpty == true
              ? email!
              : '未知使用者';

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
