import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
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
    return DiagnosticLog.instance.trace('登出', () async {
      return _client.auth.signOut();
    });
  }

  /// Returns `true` if the OAuth browser flow was launched successfully.
  /// Supabase will deliver the session via [authStateChanges] once the user
  /// completes authorisation and the deep-link / redirect is received.
  Future<bool> signInWithGoogle() {
    return DiagnosticLog.instance.trace('開啟 Google 登入', () async {
      return _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirectTo,
      );
    });
  }

  Future<bool> signInWithApple() {
    return DiagnosticLog.instance.trace('開啟 Apple 登入', () async {
      return _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _oauthRedirectTo,
      );
    });
  }

  /// Redirect URI sent to Supabase.
  /// - Web: the current page URL without hash/query so GitHub Pages subpaths work.
  /// - Mobile: a custom deep-link scheme registered in AndroidManifest / Info.plist.
  static String get _oauthRedirectTo {
    if (kIsWeb) {
      return Uri.base.removeFragment().replace(query: '').toString();
    }
    return 'com.example.tripplannerapp://login-callback';
  }
}
