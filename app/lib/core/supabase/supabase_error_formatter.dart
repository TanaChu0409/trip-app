import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_photo_upload_preparer.dart';

class SupabaseErrorFormatter {
  const SupabaseErrorFormatter._();

  static String userMessage(Object error) {
    final normalized = error.toString().toLowerCase();
    if (error is StateError &&
        error.message
            .toString()
            .contains('Missing required environment variable')) {
      return '服務暫時無法使用，請稍後再試。';
    }
    if (error is StopPhotoUploadException) {
      return switch (error.code) {
        StopPhotoUploadErrorCode.unsupportedImageFormat =>
          '不支援的圖片格式，請改用 JPEG、PNG 或 WebP。',
        StopPhotoUploadErrorCode.invalidImageData => '這張圖片檔案已損毀或無法讀取，請改選其他照片。',
        StopPhotoUploadErrorCode.iphoneImageConversionFailed =>
          '目前無法處理這張 iPhone 圖片，請先轉成 JPEG 或 PNG 後再試。',
      };
    }
    if (error is ArgumentError &&
        error.message == '不支援的圖片格式，請改用 JPEG、PNG 或 WebP。') {
      return '不支援的圖片格式，請改用 JPEG、PNG 或 WebP。';
    }
    if (normalized.contains('failed host lookup') ||
        normalized.contains('socketexception') ||
        normalized.contains('xmlhttprequest') ||
        normalized.contains('failed to fetch') ||
        normalized.contains('network') ||
        normalized.contains('timed out') ||
        normalized.contains('clientexception')) {
      return '無法連線，請檢查網路連線後再試。';
    }
    if (normalized.contains('jwt') ||
        normalized.contains('refresh token') ||
        normalized.contains('session expired') ||
        normalized.contains('登入狀態已失效') ||
        (error is PostgrestException && error.code == 'PGRST301') ||
        (error is StorageException && error.statusCode == '401')) {
      return '登入狀態已失效，請重新登入後再試。';
    }
    if (error is AuthException) {
      return '登入失敗，請稍後再試。';
    }
    if (error is StorageException) {
      final message = error.message.toLowerCase();
      if (message.contains('object not found')) {
        return '找不到這張照片，請重新整理後再試。';
      }
      if (message.contains('bucket not found')) {
        return '照片服務暫時無法使用，請稍後再試。';
      }
      if (message.contains('signed') && message.contains('url')) {
        return '暫時無法顯示照片，請稍後重新整理再試。';
      }
      if (error.statusCode == '403' ||
          message.contains('row-level security') ||
          message.contains('unauthorized') ||
          message.contains('permission')) {
        return '目前無法存取照片，請確認你有編輯此旅程的權限，或稍後再試。';
      }
      return '照片操作失敗，請稍後再試。';
    }
    if (error is PostgrestException) {
      if (error.code == '42501' || normalized.contains('row-level security')) {
        return '目前無法完成操作，請確認你有操作此旅程的權限，或稍後再試。';
      }
      if (error.code == '23503') {
        return '相關資料可能已變更，請重新整理後再試。';
      }
    }
    return '操作失敗，請稍後再試。';
  }

  static String diagnosticDetails(Object error) {
    if (error is StopPhotoUploadException) {
      return error.diagnosticMessage;
    }
    if (error is AuthException) {
      return error.message;
    }
    if (error is StorageException) {
      final statusCode =
          error.statusCode == null ? 'unknown' : '${error.statusCode}';
      final reason = _classifyStorageFailure(error.message);
      return '[storage:$statusCode:$reason] ${error.message}'.trim();
    }
    if (error is PostgrestException) {
      final code =
          error.code == null || error.code!.isEmpty ? 'unknown' : error.code!;
      return '[$code] ${error.message}'.trim();
    }
    return error.toString();
  }

  static String _classifyStorageFailure(String message) {
    final normalized = message.trim().toLowerCase();

    if (normalized.contains('bucket not found') ||
        normalized.contains('object not found')) {
      return 'missing-object';
    }
    if (normalized.contains('signed') && normalized.contains('url')) {
      return 'signed-url';
    }
    if (normalized.contains('row-level security')) {
      return 'rls';
    }
    if (normalized.contains('unauthorized')) {
      return 'unauthorized';
    }
    if (normalized.contains('permission')) {
      return 'permission';
    }
    return 'other';
  }
}
