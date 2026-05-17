import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseErrorFormatter {
  const SupabaseErrorFormatter._();

  static String userMessage(Object error) {
    if (error is StateError) {
      final message = error.message.toString();
      if (message.contains('Missing required environment variable')) {
        return '缺少 Supabase 設定。請用 --dart-define 或 --dart-define-from-file 提供 SUPABASE_URL 與 SUPABASE_ANON_KEY。';
      }
      if (_containsCjk(message)) {
        return message;
      }
    }

    if (error is ArgumentError) {
      final message = error.message?.toString() ?? '';
      if (message.contains('不支援的圖片格式') ||
          message.contains('iPhone 圖片') ||
          _containsCjk(message)) {
        return message;
      }
    }

    if (error is AuthException) {
      return error.message;
    }

    if (error is StorageException) {
      final message = error.message.trim();
      final normalized = message.toLowerCase();

      if (normalized.contains('object not found') ||
          normalized.contains('bucket not found')) {
        return '找不到照片儲存空間。請確認已執行 stop photos 相關的 Supabase migration。';
      }

      if (normalized.contains('row-level security') ||
          normalized.contains('unauthorized') ||
          normalized.contains('permission')) {
        return 'Supabase 儲存空間權限擋下這次照片操作。請確認 stop-photos bucket 與 storage policy 已正確部署。';
      }

      if (message.isNotEmpty) {
        return '照片上傳失敗：$message';
      }
    }

    if (error is PostgrestException) {
      final message = error.message.trim();
      final normalized = message.toLowerCase();

      if (error.code == '42501' || normalized.contains('row-level security')) {
        return 'Supabase 權限設定擋下這次操作。請確認已執行所有 migration，尤其是 child tables 與 shared_access 的 RLS policy。';
      }

      if (error.code == '23503') {
        return '關聯資料不存在或尚未同步完成，請重新整理後再試一次。';
      }

      if (error.code == 'PGRST301' || normalized.contains('jwt')) {
        return '登入狀態已失效，請重新登入後再試。';
      }

      if (message.isNotEmpty) {
        return 'Supabase 回傳錯誤：$message';
      }
    }

    final fallback = error.toString().toLowerCase();
    if (fallback.contains('failed host lookup') ||
        fallback.contains('socketexception') ||
        fallback.contains('xmlhttprequest') ||
        fallback.contains('failed to fetch') ||
        fallback.contains('network') ||
        fallback.contains('timed out') ||
        fallback.contains('clientexception')) {
      return '無法連線到 Supabase。請確認網路、SUPABASE_URL 是否正確，以及 Supabase 專案是否可存取。';
    }

    return '操作失敗，請稍後再試。';
  }

  static String diagnosticDetails(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    if (error is PostgrestException) {
      final code = error.code == null || error.code!.isEmpty
          ? 'unknown'
          : error.code!;
      return '[$code] ${error.message}'.trim();
    }
    return error.toString();
  }

  static bool _containsCjk(String value) {
    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(value);
  }
}
