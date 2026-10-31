import 'package:flutter/foundation.dart';
import 'diagnostic_log.dart';

class DiagnosticErrors {
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    final flutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      DiagnosticLog.instance
          .error('Flutter 錯誤', details.exception, details.stack);
      flutterHandler?.call(details);
    };
    final platformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      DiagnosticLog.instance.error('未處理錯誤', error, stack);
      return platformHandler?.call(error, stack) ?? false;
    };
  }
}
