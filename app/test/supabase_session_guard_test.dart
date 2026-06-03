import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_session_guard.dart';

void main() {
  group('SupabaseSessionGuard', () {
    test('detects auth session expiry', () {
      const error = AuthException('Session expired');

      expect(SupabaseSessionGuard.isSessionExpiredError(error), isTrue);
    });

    test('detects PostgREST JWT failures', () {
      const error = PostgrestException(
        message: 'JWT expired',
        code: 'PGRST301',
      );

      expect(SupabaseSessionGuard.isSessionExpiredError(error), isTrue);
    });

    test('detects storage unauthorized failures', () {
      const error = StorageException(
        'Unauthorized',
        statusCode: '401',
      );

      expect(SupabaseSessionGuard.isSessionExpiredError(error), isTrue);
    });

    test('does not treat row-level security as session expiry', () {
      const error = PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      );

      expect(SupabaseSessionGuard.isSessionExpiredError(error), isFalse);
    });
  });
}
