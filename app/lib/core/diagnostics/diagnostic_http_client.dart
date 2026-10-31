import 'dart:async';
import 'package:http/http.dart' as http;
import 'diagnostic_log.dart';
import 'diagnostic_sanitizer.dart';

class DiagnosticHttpClient extends http.BaseClient {
  DiagnosticHttpClient(this.inner, {DiagnosticLog? log})
      : log = log ?? DiagnosticLog.instance;
  final http.Client inner;
  final DiagnosticLog log;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!log.enabled) return inner.send(request);
    final generation = log.generation;
    final operation = log.operationId;
    final id = log.nextId('request');
    final watch = Stopwatch()..start();
    final startedAt = DateTime.now();
    final isAuth = request.url.path.startsWith('/auth/');
    final requestBody = DiagnosticBody();
    final responseBody = DiagnosticBody();
    var requestLogged = false;
    var responseLogged = false;
    void recordRequest() {
      if (requestLogged) return;
      requestLogged = true;
      log.network(
          response: false,
          requestId: id,
          operation: operation,
          method: request.method,
          url: request.url,
          headers: request.headers,
          body: requestBody,
          at: startedAt,
          generation: generation);
      requestBody.discard();
    }

    void recordResponse(http.StreamedResponse? response,
        {Object? error, StackTrace? stack, bool cancelled = false}) {
      if (responseLogged) return;
      responseLogged = true;
      recordRequest();
      log.network(
          response: true,
          requestId: id,
          operation: operation,
          method: request.method,
          url: request.url,
          headers: response?.headers ?? const {},
          body: responseBody,
          generation: generation,
          status: response?.statusCode,
          elapsedMs: watch.elapsedMilliseconds,
          error: error,
          stack: stack,
          cancelled: cancelled);
      responseBody.discard();
    }

    try {
      final wrapped = _ObservedRequest(
          request,
          (source) => _observe(
                source,
                onData: (bytes) {
                  if (!log.accepts(generation)) requestBody.discard();
                  requestBody.add(bytes,
                      capture: !isAuth &&
                          log.accepts(generation) &&
                          DiagnosticSanitizer.isJson(
                              request.headers['content-type']));
                },
                onDone: () {
                  requestBody.complete = true;
                  recordRequest();
                },
                onError: (e, st) {
                  recordRequest();
                },
                onCancel: recordRequest,
              ));
      final response = await inner.send(wrapped);
      recordRequest();
      final stream = _observe(
        response.stream,
        onData: (bytes) {
          if (!log.accepts(generation)) responseBody.discard();
          responseBody.add(bytes,
              capture: !isAuth &&
                  log.accepts(generation) &&
                  DiagnosticSanitizer.isJson(response.headers['content-type']));
        },
        onDone: () {
          responseBody.complete = true;
          recordResponse(response);
        },
        onError: (e, st) => recordResponse(response,
            error: e, stack: st, cancelled: e is http.RequestAbortedException),
        onCancel: () => recordResponse(response, cancelled: true),
      );
      if (response is http.BaseResponseWithUrl) {
        return _ResponseWithUrl(stream, response.statusCode,
            url: (response as http.BaseResponseWithUrl).url,
            contentLength: response.contentLength,
            request: request,
            headers: response.headers,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
            reasonPhrase: response.reasonPhrase);
      }
      return http.StreamedResponse(stream, response.statusCode,
          contentLength: response.contentLength,
          request: request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase);
    } catch (e, st) {
      recordResponse(null,
          error: e, stack: st, cancelled: e is http.RequestAbortedException);
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}

// Forward cancellation, pause/resume, original bytes and stream errors. No
// response is subscribed to until its consumer starts listening.
Stream<List<int>> _observe(
  Stream<List<int>> source, {
  required void Function(List<int>) onData,
  required void Function() onDone,
  required void Function(Object, StackTrace) onError,
  required void Function() onCancel,
}) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  var done = false;
  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      subscription = source.listen((bytes) {
        onData(bytes);
        controller.add(bytes);
      }, onError: (Object e, StackTrace st) {
        onError(e, st);
        controller.addError(e, st);
      }, onDone: () {
        done = true;
        onDone();
        controller.close();
      });
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      if (!done) onCancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

class _ResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _ResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });
  @override
  final Uri url;
}

class _ObservedRequest extends http.BaseRequest with http.Abortable {
  _ObservedRequest(this.original, this.observe)
      : super(original.method, original.url) {
    headers.addAll(original.headers);
    followRedirects = original.followRedirects;
    maxRedirects = original.maxRedirects;
    persistentConnection = original.persistentConnection;
  }
  final http.BaseRequest original;
  final Stream<List<int>> Function(Stream<List<int>>) observe;
  @override
  Future<void>? get abortTrigger => original is http.Abortable
      ? (original as http.Abortable).abortTrigger
      : null;
  @override
  int? get contentLength => original.contentLength;
  @override
  http.ByteStream finalize() {
    super.finalize();
    // Multipart finalize() adds its boundary header. Copy headers afterwards.
    final stream = original.finalize();
    headers
      ..clear()
      ..addAll(original.headers);
    return http.ByteStream(observe(stream));
  }
}
