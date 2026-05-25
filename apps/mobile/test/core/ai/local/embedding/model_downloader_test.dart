/// Downloader integration tests against a localhost HTTP server.
/// Faster + more honest than mocking Dio — exercises the real
/// stream → .partial → rename → SHA-verify pipeline end to end.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_downloader.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:path/path.dart' as p;

typedef _Handler = Future<void> Function(HttpRequest);

class _LocalServer {
  _LocalServer._(this._server, this.port);
  final HttpServer _server;
  final int port;
  Future<void> close() => _server.close(force: true);

  static Future<_LocalServer> start(_Handler handler) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      try {
        await handler(req);
      } catch (_) {}
    });
    return _LocalServer._(server, server.port);
  }
}

Uint8List _bytes(int len, {int seed = 0}) {
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = (seed + i) & 0xFF;
  }
  return out;
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dl-');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('ModelDownloader.download', () {
    test('happy path: streams to .partial, renames on success', () async {
      final payload = _bytes(8192);
      final server = await _LocalServer.start((req) async {
        req.response.headers.contentType =
            ContentType('application', 'octet-stream');
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });
      addTearDown(server.close);

      final dl = ModelDownloader();
      var lastReceived = -1;
      int? lastTotal;
      await dl.download(
        file: ModelFile(
          localName: 'thing.bin',
          url: 'http://127.0.0.1:${server.port}/x',
          sizeBytes: payload.length,
        ),
        destDir: tmp.path,
        onProgress: (received, total) {
          lastReceived = received;
          lastTotal = total;
        },
      );

      final outFile = File(p.join(tmp.path, 'thing.bin'));
      expect(outFile.existsSync(), isTrue);
      expect(await outFile.length(), payload.length);
      expect(lastReceived, payload.length);
      expect(lastTotal, payload.length);
      // No leftover .partial
      expect(File(p.join(tmp.path, 'thing.bin.partial')).existsSync(), isFalse);
    });

    test('sha256 match: succeeds', () async {
      final payload = _bytes(2048, seed: 7);
      final expected = _sha256Hex(payload);
      final server = await _LocalServer.start((req) async {
        req.response.add(payload);
        await req.response.close();
      });
      addTearDown(server.close);

      await ModelDownloader().download(
        file: ModelFile(
          localName: 'verified.bin',
          url: 'http://127.0.0.1:${server.port}/y',
          sha256: expected,
        ),
        destDir: tmp.path,
      );
      expect(File(p.join(tmp.path, 'verified.bin')).existsSync(), isTrue);
    });

    test('sha256 mismatch: throws + deletes partial', () async {
      final payload = _bytes(2048, seed: 9);
      final server = await _LocalServer.start((req) async {
        req.response.add(payload);
        await req.response.close();
      });
      addTearDown(server.close);

      await expectLater(
        () => ModelDownloader().download(
          file: ModelFile(
            localName: 'bad.bin',
            url: 'http://127.0.0.1:${server.port}/z',
            sha256: '0' * 64,
          ),
          destDir: tmp.path,
        ),
        throwsA(isA<ChecksumMismatch>()),
      );
      expect(File(p.join(tmp.path, 'bad.bin')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'bad.bin.partial')).existsSync(), isFalse);
    });

    test('cancel: aborts download + cleans .partial', () async {
      // Server that drips bytes slowly so we can cancel mid-stream.
      final server = await _LocalServer.start((req) async {
        req.response.headers.contentType =
            ContentType('application', 'octet-stream');
        // 1 MB total declared; emit slowly.
        req.response.contentLength = 1024 * 1024;
        try {
          for (var i = 0; i < 16; i++) {
            req.response.add(_bytes(64 * 1024, seed: i));
            await req.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await req.response.close();
        } on Object {
          // client disconnected — expected after cancel
        }
      });
      addTearDown(server.close);

      final cancel = DownloadCancellation();
      final dl = ModelDownloader();
      final fut = dl.download(
        file: ModelFile(
          localName: 'slow.bin',
          url: 'http://127.0.0.1:${server.port}/s',
          sizeBytes: 1024 * 1024,
        ),
        destDir: tmp.path,
        cancel: cancel,
      );
      // Let some bytes flow, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      cancel.cancel();

      await expectLater(fut, throwsA(isA<StateError>()));
      expect(File(p.join(tmp.path, 'slow.bin')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'slow.bin.partial')).existsSync(), isFalse);
    });

    test('replaces existing final file on re-download', () async {
      final oldPayload = _bytes(100, seed: 1);
      final newPayload = _bytes(200, seed: 2);
      await File(p.join(tmp.path, 'rewrite.bin')).writeAsBytes(oldPayload);

      final server = await _LocalServer.start((req) async {
        req.response.add(newPayload);
        await req.response.close();
      });
      addTearDown(server.close);

      await ModelDownloader().download(
        file: ModelFile(
          localName: 'rewrite.bin',
          url: 'http://127.0.0.1:${server.port}/r',
          sizeBytes: newPayload.length,
        ),
        destDir: tmp.path,
      );
      final bytes = await File(p.join(tmp.path, 'rewrite.bin')).readAsBytes();
      expect(bytes.length, newPayload.length);
      expect(bytes[0], newPayload[0]);
    });
  });
}
