import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_sanitizer.dart';

void main() {
  test('sanitizes nested payloads, identifiers, URLs, headers and mixed errors',
      () {
    final s = DiagnosticSanitizer();
    final safe = jsonEncode(s.body({
      'id': 'private-user',
      'trip_id': 'private-user',
      'permission': 'editor',
      'email': 'alice@example.com',
      'name': '王小明',
      'title': '私人旅行',
      'note': 'secret note',
      'access_token': 'secret-access',
      'refresh_token': 'secret-refresh',
      'password': 'secret-password',
      'signedUrl': 'https://private.test/photo?token=secret-signature',
      'data': [
        {'id': 'another-id', 'is_archived': true}
      ],
      'unexpected-secret-key': 'secret-value',
    }));
    expect(safe, contains('editor'));
    expect(safe, contains('ref-1'));
    expect(s.alias('private-user'), 'ref-1');
    for (final secret in [
      'private-user',
      'alice@example.com',
      '王小明',
      '私人旅行',
      'secret-',
      'private.test',
      'unexpected-secret-key'
    ]) {
      expect(safe, isNot(contains(secret)));
    }
    final url = s.path(Uri.parse('https://private.test/rest/v1/trips'
        '?id=eq.private-user&token=secret-token&email=eq.alice@example.com#secret'));
    expect(url, contains('eq.ref-1'));
    expect(url, isNot(contains('private.test')));
    expect(url, isNot(contains('alice')));
    expect(url, isNot(contains('secret')));
    expect(
        s.headers({
          'Authorization': 'Bearer secret',
          'Cookie': 'secret',
          'apikey': 'secret',
          'Content-Type': 'application/json; secret=hidden',
          'Location': 'https://secret.test',
          'Content-Length': '123'
        }),
        {'content-type': 'application/json', 'content-length': '123'});
    final error = jsonEncode(s.error(
        StateError('王小明 SQL 42501 secret@example.com '
            'Bearer secret https://test/photo?token=secret'),
        StackTrace.fromString(
            '#0 fn (package:trip_planner_app/main.dart:10:5)\n'
            '#1 private user secret /home/alice/file.dart:1:2')));
    expect(error, contains('42501'));
    expect(error, contains('main.dart:10:5'));
    expect(error, isNot(contains('王小明')));
    expect(error, isNot(contains('secret')));
    expect(error, isNot(contains('/home/alice')));
  });

  test(
      'body captures are bounded, marked and never retain binary or invalid JSON',
      () {
    final s = DiagnosticSanitizer();
    final body = DiagnosticBody()
      ..add(utf8.encode('{"permission":"editor"}'), capture: true)
      ..complete = true;
    expect(body.snapshot(s, 'application/json')['content'],
        {'permission': 'editor'});
    final large = DiagnosticBody()
      ..add(List.filled(9000, 65), capture: true)
      ..complete = true;
    expect(large.snapshot(s, 'application/json'), {
      'observedBytes': 9000,
      'complete': true,
      'truncated': true,
      'omitted': true,
    });
    for (final mime in ['image/jpeg', 'application/json', 'text/plain']) {
      final invalid = DiagnosticBody()
        ..add(utf8.encode('secret raw data'), capture: true)
        ..complete = true;
      final snapshot = jsonEncode(invalid.snapshot(s, mime));
      expect(snapshot, isNot(contains('secret')));
      expect(snapshot, contains('omitted'));
    }
  });

  test('bounded store, toggle, eviction, clear and single entry export',
      () async {
    final log = DiagnosticLog(maxEntries: 2, maxBytes: 1000);
    log.event(DiagnosticKind.operation, '一');
    final old = log.entries.first;
    log.event(DiagnosticKind.operation, '二');
    log.event(DiagnosticKind.operation, '三');
    expect(log.entries.length, 2);
    expect(log.droppedEntries, 1);
    expect(log.retainedBytes, lessThanOrEqualTo(1000));
    expect((jsonDecode(log.export(old))['entries'] as List), isEmpty);
    final generation = log.generation;
    log.enabled = false;
    log.event(DiagnosticKind.operation, '不記錄');
    expect(log.entries.length, 2);
    log.enabled = true;
    expect(log.accepts(generation), isFalse);
    final export = jsonDecode(log.export(log.entries.first));
    expect(export['formatVersion'], 1);
    expect(export['entries'], hasLength(1));
    log.signedOut();
    expect(log.entries.single.label, '登出完成');
    log.clear();
    expect(log.entries, isEmpty);
    expect(log.retainedBytes, 0);
    await Future<void>.delayed(Duration.zero);
    log.dispose();
  });

  test('byte capacity evicts even before entry capacity', () async {
    final log = DiagnosticLog(maxBytes: 300);
    for (var i = 0; i < 20; i++) {
      log.event(DiagnosticKind.operation, '測試');
    }
    expect(log.retainedBytes, lessThanOrEqualTo(300));
    expect(log.droppedEntries, greaterThan(0));
    await Future<void>.delayed(Duration.zero);
    log.dispose();
  });

  test('nested and concurrent operations correlate and errors are deduplicated',
      () async {
    final log = DiagnosticLog();
    final gate = Completer<void>();
    final ids = <String?>[];
    final first = log.trace('第一組', () async {
      ids.add(log.operationId);
      await gate.future;
      await log.trace('子操作', () async {
        ids.add(log.operationId);
      });
    });
    await log.trace('第二組', () async {
      ids.add(log.operationId);
    });
    gate.complete();
    await first;
    expect(ids[0], ids[2]);
    expect(ids[0], isNot(ids[1]));
    final failure = StateError('secret');
    await expectLater(
        log.trace(
            '失敗',
            () => log.trace('巢狀失敗', () async {
                  log.error('已捕捉', failure, StackTrace.current);
                  throw failure;
                })),
        throwsStateError);
    expect(log.entries.where((e) => e.kind == 'error'), hasLength(1));
    await log.trace('部分失敗', () async {
      log.markFailed();
    });
    expect(log.entries.last.outcome, 'failure');
    expect(log.export(), isNot(contains('secret')));
    log.enabled = false;
    final count = log.entries.length;
    expect(await log.trace('關閉', () async => 42), 42);
    expect(log.entries.length, count);
    await Future<void>.delayed(Duration.zero);
    log.dispose();
  });
}
