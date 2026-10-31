import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_http_client.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closed = true;
  }
}

void main() {
  late DiagnosticLog log;
  setUp(() {
    log = DiagnosticLog();
  });

  test('authentication bodies are omitted even for otherwise allowed fields',
      () async {
    final client = DiagnosticHttpClient(
        MockClient((_) async => http.Response(
            '{"code":"42501","id":"private","expires_in":3600}', 200,
            headers: {'content-type': 'application/json'})),
        log: log);
    await client.post(Uri.parse('https://test/auth/v1/token'),
        headers: {'content-type': 'application/json'},
        body: '{"code":"42501"}');
    expect(log.export(), isNot(contains('42501')));
    expect(log.export(), isNot(contains('3600')));
    expect(log.export(), contains('omitted'));
  });
  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    log.dispose();
  });

  test('preserves request and response, records sanitized correlated data',
      () async {
    final client = DiagnosticHttpClient(MockClient((request) async {
      expect(request.body, '{"title":"private trip","permission":"editor"}');
      expect(request.headers['authorization'], 'Bearer secret-token');
      return http.Response(
          '{"id":"private-id","permission":"viewer",'
          '"email":"secret@example.com"}',
          201,
          headers: {
            'content-type': 'application/json',
            'set-cookie': 'private'
          });
    }), log: log);
    final response = await log.trace(
        '建立旅程',
        () => client.post(
              Uri.parse('https://project.test/rest/v1/trips?secret=hidden'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer secret-token'
              },
              body: '{"title":"private trip","permission":"editor"}',
            ));
    expect(response.statusCode, 201);
    expect(response.body, contains('secret@example.com'));
    final network = log.entries
        .where((e) => ['request', 'response'].contains(e.kind))
        .toList();
    expect(network, hasLength(2));
    expect(network[0].toJson()['details']['requestId'],
        network[1].toJson()['details']['requestId']);
    expect(
        network[0].toJson()['operationId'], network[1].toJson()['operationId']);
    expect(network[0].toJson()['operationId'], isNotNull);
    final exported = log.export();
    for (final secret in [
      'private trip',
      'private-id',
      'secret@example.com',
      'secret-token',
      'set-cookie',
      'project.test',
      'hidden'
    ]) {
      expect(exported, isNot(contains(secret)));
    }
    expect(exported, contains('editor'));
    expect(exported, contains('viewer'));
    client.close();
  });

  test('non-success and send exceptions retain original behavior', () async {
    final client = DiagnosticHttpClient(
        MockClient((_) async => http.Response('private error', 403)),
        log: log);
    expect((await client.get(Uri.parse('https://test/rest/v1/trips'))).body,
        'private error');
    expect(log.entries.last.outcome, 'failure');
    final error = http.ClientException('network secret');
    final failing =
        DiagnosticHttpClient(StreamClient((_) async => throw error), log: log);
    await expectLater(
        failing.get(Uri.parse('https://test')), throwsA(same(error)));
    expect(log.entries.last.outcome, 'failure');
    expect(log.export(), isNot(contains('network secret')));
  });

  test('stream is lazy, errors are forwarded once and cancellation propagates',
      () async {
    var listened = false;
    var cancelled = false;
    late StreamController<List<int>> source;
    source = StreamController(onListen: () {
      listened = true;
    }, onCancel: () {
      cancelled = true;
    });
    final client = DiagnosticHttpClient(
        StreamClient((_) async => http.StreamedResponse(source.stream, 200,
            headers: {'content-type': 'application/json'})),
        log: log);
    final response =
        await client.send(http.Request('GET', Uri.parse('https://test')));
    expect(listened, isFalse);
    final errors = <Object>[];
    final subscription = response.stream.listen((_) {}, onError: errors.add);
    expect(listened, isTrue);
    final error = StateError('secret');
    source.addError(error, StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(errors, [error]);
    await subscription.cancel();
    expect(cancelled, isTrue);
    expect(log.entries.where((e) => e.kind == 'response'), hasLength(1));
    expect(log.entries.last.outcome, 'failure');
    await source.close();
  });

  test('cancellation without errors is recorded', () async {
    final source = StreamController<List<int>>();
    final client = DiagnosticHttpClient(
        StreamClient((_) async => http.StreamedResponse(source.stream, 200)),
        log: log);
    final response =
        await client.send(http.Request('GET', Uri.parse('https://test')));
    final sub = response.stream.listen((_) {});
    await sub.cancel();
    expect(log.entries.last.outcome, 'cancelled');
    await source.close();
  });

  test('abort trigger is observed by transport and original abort is rethrown',
      () async {
    final abort = Completer<void>();
    final error = http.RequestAbortedException();
    final client = DiagnosticHttpClient(StreamClient((request) async {
      await (request as http.Abortable).abortTrigger;
      throw error;
    }), log: log);
    final result = client.send(http.AbortableRequest(
        'GET', Uri.parse('https://test'),
        abortTrigger: abort.future));
    final assertion = expectLater(result, throwsA(same(error)));
    abort.complete();
    await assertion;
    expect(log.entries.last.outcome, 'cancelled');
  });

  test('multipart boundaries, bytes, options and abort triggers are preserved',
      () async {
    final abort = Completer<void>();
    final inner = StreamClient((request) async {
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 2);
      expect(request.persistentConnection, isFalse);
      expect((request as http.Abortable).abortTrigger, same(abort.future));
      expect(await request.finalize().toBytes(), [1, 2, 3]);
      return http.StreamedResponse(Stream.value([4, 5]), 200);
    });
    final client = DiagnosticHttpClient(inner, log: log);
    final request = http.AbortableRequest(
        'PUT', Uri.parse('https://test/storage/v1/object/stop-photos/photo'),
        abortTrigger: abort.future)
      ..bodyBytes = [1, 2, 3]
      ..followRedirects = false
      ..maxRedirects = 2
      ..persistentConnection = false;
    expect(await (await client.send(request)).stream.toBytes(), [4, 5]);
    final multipartClient = DiagnosticHttpClient(StreamClient((request) async {
      final stream = request.finalize();
      final body = await stream.bytesToString();
      expect(body, contains('private-file-name'));
      expect(request.headers['content-type'], contains('boundary='));
      return http.StreamedResponse(const Stream.empty(), 204);
    }), log: log);
    final multipart = http.MultipartRequest(
        'POST', Uri.parse('https://test/storage/v1/object'))
      ..files.add(http.MultipartFile.fromString('photo', 'private image bytes',
          filename: 'private-file-name'));
    await (await multipartClient.send(multipart)).stream.drain<void>();
    expect(log.export(), isNot(contains('private image bytes')));
    expect(log.export(), isNot(contains('private-file-name')));
    client.close();
    expect(inner.closed, isTrue);
  });

  test('disabled or cleared captures cannot repopulate logs', () async {
    final source = StreamController<List<int>>();
    final client = DiagnosticHttpClient(StreamClient((request) async {
      await request.finalize().drain<void>();
      return http.StreamedResponse(source.stream, 200,
          headers: {'content-type': 'application/json'});
    }), log: log);
    final response =
        await client.send(http.Request('GET', Uri.parse('https://test')));
    final result = response.stream.toBytes();
    source.add(utf8.encode('{"permission":'));
    log.enabled = false;
    log.clear();
    log.enabled = true;
    source.add(utf8.encode('"editor"}'));
    await source.close();
    await result;
    expect(log.entries, isEmpty);
    log.enabled = false;
    final direct = http.Request('GET', Uri.parse('https://test'));
    final disabled = DiagnosticHttpClient(StreamClient((request) async {
      expect(request, same(direct));
      return http.StreamedResponse(const Stream.empty(), 200);
    }), log: log);
    await (await disabled.send(direct)).stream.drain<void>();
    expect(log.entries, isEmpty);
  });
}
