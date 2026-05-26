import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Minimal HttpClientAdapter that returns canned responses keyed by request
/// path. Each entry can be one of:
///   * `Map` / `List` → JSON-encoded body, status 200.
///   * `String`       → raw text (for legacy CSV-ish endpoints e.g. Sina).
///   * `_CannedResponse` → full control over status, body, headers.
///
/// Multiple responses can be queued per path; the adapter consumes them in
/// FIFO order so retry tests can simulate "first call fails, second succeeds".
class CannedAdapter implements HttpClientAdapter {
  final Map<String, List<CannedResponse>> _queues = {};
  final List<RequestOptions> calls = [];

  void enqueue(String pathContains, Object body, {int status = 200}) {
    _queues
        .putIfAbsent(pathContains, () => [])
        .add(CannedResponse(body, status: status));
  }

  void enqueueRaw(String pathContains, CannedResponse response) {
    _queues.putIfAbsent(pathContains, () => []).add(response);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    for (final entry in _queues.entries) {
      if (url.contains(entry.key) && entry.value.isNotEmpty) {
        final c = entry.value.removeAt(0);
        return _toBody(c, options);
      }
    }
    return ResponseBody.fromString(
      'no canned response for $url',
      404,
      headers: const {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );
  }

  ResponseBody _toBody(CannedResponse c, RequestOptions options) {
    final body = c.body;
    if (body is Uint8List) {
      return ResponseBody.fromBytes(
        body,
        c.status,
        headers:
            c.headers ??
            const {
              Headers.contentTypeHeader: ['application/octet-stream'],
            },
      );
    }
    if (body is String) {
      return ResponseBody.fromString(
        body,
        c.status,
        headers:
            c.headers ??
            const {
              Headers.contentTypeHeader: ['text/plain'],
            },
      );
    }
    final encoded = jsonEncode(body);
    return ResponseBody.fromString(
      encoded,
      c.status,
      headers:
          c.headers ??
          const {
            Headers.contentTypeHeader: ['application/json'],
          },
    );
  }

  @override
  void close({bool force = false}) {}
}

class CannedResponse {
  CannedResponse(this.body, {this.status = 200, this.headers});
  final Object body;
  final int status;
  final Map<String, List<String>>? headers;
}
