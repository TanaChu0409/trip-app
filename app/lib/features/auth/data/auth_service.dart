import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  /// Returns `true` if the OAuth browser flow was launched successfully.
  /// Supabase will deliver the session via [authStateChanges] once the user
  /// completes authorisation and the deep-link / redirect is received.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectTo,
    );
  }

  Future<bool> signInWithApple() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _oauthRedirectTo,
    );
  }

  /// Redirect URI sent to Supabase.
  /// - Web: the current page origin (Supabase redirects back here).
  /// - Mobile: a custom deep-link scheme registered in AndroidManifest / Info.plist.
  static String get _oauthRedirectTo {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return 'com.example.tripplannerapp://login-callback';
  }
}