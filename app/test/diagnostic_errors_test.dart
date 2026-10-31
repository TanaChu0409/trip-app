import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_errors.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global error hooks preserve prior handlers and deduplicate errors',
      () async {
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var flutterCalls = 0;
    var platformCalls = 0;
    FlutterError.onError = (_) {
      flutterCalls++;
    };
    PlatformDispatcher.instance.onError = (_, __) {
      platformCalls++;
      return true;
    };
    final log = DiagnosticLog.instance..clear();
    try {
      DiagnosticErrors.install();
      final handler = FlutterError.onError;
      DiagnosticErrors.install();
      expect(FlutterError.onError, same(handler));
      final error = StateError('private@example.com secret');
      final stack = StackTrace.current;
      FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack));
      expect(PlatformDispatcher.instance.onError!(error, stack), isTrue);
      expect(flutterCalls, 1);
      expect(platformCalls, 1);
      expect(log.entries.where((e) => e.kind == 'error'), hasLength(1));
      expect(log.export(), isNot(contains('private@example.com')));
    } finally {
      FlutterError.onError = oldFlutter;
      PlatformDispatcher.instance.onError = oldPlatform;
      log.clear();
      await Future<void>.delayed(Duration.zero);
    }
  });
}
