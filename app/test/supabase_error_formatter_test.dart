import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';

void main() {
  group('SupabaseErrorFormatter', () {
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
        'Supabase 儲存空間權限擋下這次照片操作。請確認 stop-photos bucket 與 storage policy 已正確部署。',
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
        '照片已上傳，但無法取得顯示連結，請稍後重新整理再試。',
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
