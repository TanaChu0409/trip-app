import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_session_guard.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class SessionExpiryHandler {
  const SessionExpiryHandler._();

  static Future<bool> signOutIfSessionExpired(Object error) async {
    if (!SupabaseSessionGuard.isSessionExpiredError(error)) {
      return false;
    }
    if (await SupabaseSessionGuard.refreshCurrentSessionIfExpired(
      forceRefresh: true,
    )) {
      return false;
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (signOutError, stackTrace) {
      DiagnosticLog.instance.error('登入失效後登出', signOutError, stackTrace);
      debugPrint('Failed to sign out after expired session: $signOutError');
    }

    await TripStore.instance.clearForSignOut();
    return true;
  }
}
