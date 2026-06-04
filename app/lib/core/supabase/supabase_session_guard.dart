import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSessionGuard {
  const SupabaseSessionGuard._();

  static Future<bool> refreshCurrentSessionIfExpired({
    bool forceRefresh = false,
  }) async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null) {
      return false;
    }
    if (!forceRefresh && !session.isExpired) {
      return true;
    }

    try {
      await auth.refreshSession();
    } catch (_) {
      return false;
    }

    final refreshedSession = auth.currentSession;
    return refreshedSession != null && !refreshedSession.isExpired;
  }

  static bool isSessionExpiredError(Object error) {
    if (error is AuthException) {
      return _looksLikeExpiredSession(error.message);
    }

    if (error is PostgrestException) {
      final message = error.message;
      return error.code == 'PGRST301' || _looksLikeExpiredSession(message);
    }

    if (error is StorageException) {
      final statusCode = error.statusCode;
      return statusCode == '401' || _looksLikeExpiredSession(error.message);
    }

    if (error is StateError) {
      return _looksLikeExpiredSession(error.message.toString());
    }

    return _looksLikeExpiredSession(error.toString());
  }

  static bool _looksLikeExpiredSession(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('jwt') ||
        normalized.contains('session') ||
        normalized.contains('expired') ||
        normalized.contains('refresh token') ||
        normalized.contains('invalid token') ||
        normalized.contains('not authenticated') ||
        normalized.contains('user must be signed in') ||
        normalized.contains('登入狀態已失效');
  }
}
