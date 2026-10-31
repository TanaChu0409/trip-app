import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'diagnostic_sanitizer.dart';

enum DiagnosticKind { operation, request, response, error, route, realtime }

enum DiagnosticOutcome { pending, success, failure, cancelled }

class DiagnosticEntry {
  DiagnosticEntry(Map<String, Object?> value)
      : json = jsonEncode(value),
        kind = value['kind'] as String,
        outcome = value['outcome'] as String,
        label = value['label'] as String,
        time = value['time'] as String;

  // Store only an immutable, sanitized serialization. Details cannot be
  // mutated by callers after insertion; exports use this exact same payload.
  final String json;
  final String kind;
  final String outcome;
  final String label;
  final String time;
  int get bytes => utf8.encode(json).length;
  Map<String, dynamic> toJson() => jsonDecode(json) as Map<String, dynamic>;
}

class DiagnosticLog extends ChangeNotifier {
  DiagnosticLog({this.maxEntries = 500, this.maxBytes = 5 * 1024 * 1024});
  static final instance = DiagnosticLog();
  static final _operationKey = Object();
  static final _traceKey = Object();
  final int maxEntries;
  final int maxBytes;
  final sanitizer = DiagnosticSanitizer();
  final _entries = Queue<DiagnosticEntry>();
  var _seenErrors = Expando<bool>();
  bool _enabled = true;
  bool _notificationPending = false;
  int _bytes = 0;
  int _sequence = 0;
  int _generation = 0;
  int droppedEntries = 0;

  bool get enabled => _enabled;
  int get generation => _generation;
  int get retainedBytes => _bytes;
  String? get operationId => Zone.current[_operationKey] as String?;
  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);
  String nextId(String prefix) => '$prefix-${++_sequence}';
  bool accepts(int generation) => enabled && generation == _generation;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _generation++; // Also invalidates in-flight captures when toggled off/on.
    _changed();
  }

  void clear() {
    _entries.clear();
    _seenErrors = Expando<bool>();
    sanitizer.clear();
    _bytes = 0;
    droppedEntries = 0;
    _generation++;
    _changed();
  }

  void signedOut() {
    clear();
    event(DiagnosticKind.operation, '登出完成', outcome: DiagnosticOutcome.success);
  }

  // Labels are static application event names, never user input. Payloads
  // enter through the typed helpers below, not arbitrary detail maps.
  void event(
    DiagnosticKind kind,
    String label, {
    DiagnosticOutcome outcome = DiagnosticOutcome.pending,
    Object? error,
    StackTrace? stack,
    Uri? route,
    String? operation,
    int? elapsedMs,
    Object? data,
  }) {
    if (!enabled) return;
    _append(
        kind,
        label,
        outcome,
        {
          if (error != null) 'error': sanitizer.error(error, stack),
          if (route != null) 'route': sanitizer.path(route),
          if (elapsedMs != null) 'elapsedMs': elapsedMs,
          if (data != null) 'data': sanitizer.body(data),
        },
        operation: operation);
  }

  void error(String label, Object error, [StackTrace? stack]) {
    if (!enabled) return;
    // Weak identity tracking does not retain original exception messages.
    if (error is! String &&
        error is! num &&
        error is! bool &&
        error is! Record) {
      if (_seenErrors[error] == true) return;
      _seenErrors[error] = true;
    }
    event(DiagnosticKind.error, label,
        outcome: DiagnosticOutcome.failure, error: error, stack: stack);
  }

  void network({
    required bool response,
    required String requestId,
    required String? operation,
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required DiagnosticBody body,
    required int generation,
    int? status,
    int? elapsedMs,
    Object? error,
    StackTrace? stack,
    bool cancelled = false,
    DateTime? at,
  }) {
    if (!accepts(generation)) return;
    _append(
        response ? DiagnosticKind.response : DiagnosticKind.request,
        response ? 'HTTP response' : 'HTTP request',
        cancelled
            ? DiagnosticOutcome.cancelled
            : error != null || (status != null && status >= 400)
                ? DiagnosticOutcome.failure
                : response
                    ? DiagnosticOutcome.success
                    : DiagnosticOutcome.pending,
        {
          'requestId': requestId,
          'method': {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'}
                  .contains(method)
              ? method
              : '[method omitted]',
          'path': sanitizer.path(url),
          'headers': sanitizer.headers(headers),
          'body': body.snapshot(
              sanitizer, headers['content-type'] ?? headers['Content-Type']),
          if (status != null) 'status': status,
          if (elapsedMs != null) 'elapsedMs': elapsedMs,
          if (error != null) 'error': sanitizer.error(error, stack),
        },
        operation: operation,
        at: at);
  }

  void markFailed() {
    final state = Zone.current[_traceKey] as _TraceState?;
    if (state != null) state.failed = true;
  }

  Future<T> trace<T>(String label, Future<T> Function() action,
      {bool Function(T)? isSuccess}) async {
    if (!enabled) return action();
    final id = operationId ?? nextId('op');
    final generation = _generation;
    final watch = Stopwatch()..start();
    final state = _TraceState();
    return runZoned(() async {
      event(DiagnosticKind.operation, '$label：開始', operation: id);
      try {
        final result = await action();
        if (accepts(generation)) {
          event(DiagnosticKind.operation, '$label：結束',
              operation: id,
              outcome: state.failed ||
                      result == false ||
                      (isSuccess != null && !isSuccess(result))
                  ? DiagnosticOutcome.failure
                  : DiagnosticOutcome.success,
              elapsedMs: watch.elapsedMilliseconds);
        }
        return result;
      } catch (e, st) {
        if (accepts(generation)) {
          error(label, e, st);
          event(DiagnosticKind.operation, '$label：失敗',
              operation: id,
              outcome: DiagnosticOutcome.failure,
              elapsedMs: watch.elapsedMilliseconds);
        }
        rethrow;
      }
    }, zoneValues: {_operationKey: id, _traceKey: state});
  }

  void _append(DiagnosticKind kind, String label, DiagnosticOutcome outcome,
      Map<String, Object?> details,
      {String? operation, DateTime? at}) {
    final entry = DiagnosticEntry({
      'id': nextId('event'),
      'time': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'kind': kind.name,
      'outcome': outcome.name,
      'label': label,
      'operationId': operation ?? operationId,
      'details': details,
    });
    if (entry.bytes > maxBytes) {
      droppedEntries++;
      _changed();
      return;
    }
    _entries.add(entry);
    _bytes += entry.bytes;
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      _bytes -= _entries.removeFirst().bytes;
      droppedEntries++;
    }
    _changed();
  }

  String export([DiagnosticEntry? entry]) =>
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'droppedEntries': droppedEntries,
        'entries': (entry == null
                ? entries
                : _entries.contains(entry)
                    ? [entry]
                    : <DiagnosticEntry>[])
            .map((e) => e.toJson())
            .toList(),
      });

  // Network callbacks/route observers can run during widget build. Coalesce
  // notifications outside that frame without delaying collection itself.
  void _changed() {
    if (_notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      notifyListeners();
    });
  }
}

class _TraceState {
  bool failed = false;
}
