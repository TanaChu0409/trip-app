import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';

void main() {
  group('SupabaseErrorFormatter', () {
    test('maps failures without exposing backend messages', () {
      final cases = <Object, String>{
        StateError('Missing required environment variable: SUPABASE_URL'):
            '服務暫時無法使用，請稍後再試。',
        const AuthException('JWT expired'): '登入狀態已失效，請重新登入後再試。',
        const AuthException('Supabase 登入失敗 SQL'): '登入失敗，請稍後再試。',
        const AuthException('Network request failed'): '無法連線，請檢查網路連線後再試。',
        const StorageException('Object not found'): '找不到這張照片，請重新整理後再試。',
        const StorageException('Bucket not found'): '照片服務暫時無法使用，請稍後再試。',
        const StorageException('JWT expired', statusCode: '401'):
            '登入狀態已失效，請重新登入後再試。',
        const StorageException('Supabase SQL 錯誤'): '照片操作失敗，請稍後再試。',
        const PostgrestException(message: 'RLS 權限錯誤', code: '42501'):
            '目前無法完成操作，請確認你有操作此旅程的權限，或稍後再試。',
        const PostgrestException(message: 'SQL 錯誤', code: '23503'):
            '相關資料可能已變更，請重新整理後再試。',
        const PostgrestException(message: 'Supabase SQL 錯誤'): '操作失敗，請稍後再試。',
        StateError('Supabase 設定錯誤'): '操作失敗，請稍後再試。',
        ArgumentError('SQL RLS 錯誤'): '操作失敗，請稍後再試。',
        Exception('Unknown failure'): '操作失敗，請稍後再試。',
      };
      for (final entry in cases.entries) {
        final message = SupabaseErrorFormatter.userMessage(entry.key);
        expect(message, entry.value);
        expect(
            message,
            isNot(matches(
                RegExp(r'supabase|sql|jwt|rls', caseSensitive: false))));
      }
    });

    test('classifies storage row-level security failures in diagnostics', () {
      const error = StorageException(
        'new row violates row-level security policy for table "objects"',
        statusCode: '403',
      );

      expect(
        SupabaseErrorFormatter.diagnosticDetails(error),
        '[storage:403:rls] new row violates row-level security policy for table "objects"',
      );
      expect(
        SupabaseErrorFormatter.userMessage(error),
        '目前無法存取照片，請確認你有編輯此旅程的權限，或稍後再試。',
      );
    });

    test('classifies unauthorized storage failures in diagnostics', () {
      const error = StorageException(
        'Unauthorized',
        statusCode: '401',
      );

      expect(
        SupabaseErrorFormatter.diagnosticDetails(error),
        '[storage:401:unauthorized] Unauthorized',
      );
    });

    test('classifies signed url failures in diagnostics', () {
      const error = StorageException(
        'Failed to create signed URL for object',
        statusCode: '500',
      );

      expect(
        SupabaseErrorFormatter.diagnosticDetails(error),
        '[storage:500:signed-url] Failed to create signed URL for object',
      );
      expect(
        SupabaseErrorFormatter.userMessage(error),
        '暫時無法顯示照片，請稍後重新整理再試。',
      );
    });

    test('classifies missing bucket failures in diagnostics', () {
      const error = StorageException(
        'Bucket not found',
        statusCode: '404',
      );

      expect(
        SupabaseErrorFormatter.diagnosticDetails(error),
        '[storage:404:missing-object] Bucket not found',
      );
    });
  });
}
