import 'package:flutter/material.dart';
import 'diagnostic_log.dart';

class DiagnosticObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    final uri = Uri.tryParse(name);
    if (uri != null) {
      DiagnosticLog.instance.event(
        DiagnosticKind.route,
        '切換頁面',
        route: uri,
        outcome: DiagnosticOutcome.success,
      );
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);
}
