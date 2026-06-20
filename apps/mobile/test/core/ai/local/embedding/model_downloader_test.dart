/// Downloader tests using an in-memory Dio adapter.
///
/// Flutter's test binding intentionally blocks real HttpClient requests with
/// status 400, so these tests exercise the stream -> .partial -> rename ->
/// SHA-verify pipeline without touching the network stack.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/model_downloader.dart';
import 'package:naviwealth/core/ai/local/embedding/model_manifest.dart';
import 'package:path/path.dart' as p;

Uint8List _bytes(int len, {int seed = 0}) {
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = (seed + i) & 0xFF;
  }
  return out;
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

Dio _dioWith(_DownloadReply reply) =>
    Dio()..httpClientAdapter = _DownloadAdapter(reply);

class _DownloadReply {
  const _DownloadReply(
    this.payload, {
    this.chunkSize,
    this.chunkDelay = Duration.zero,
  });

  final Uint8List payload;
  final int? chunkSize;
  final Duration chunkDelay;
}

class _DownloadAdapter implements HttpClientAdapter {
  _DownloadAdapter(this.reply);

  final _DownloadReply reply;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      _streamPayload(reply),
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>[reply.payload.length.toString()],
        Headers.contentTypeHeader: <String>['application/octet-stream'],
      },
    );
  }
}

Stream<Uint8List> _streamPayload(_DownloadReply reply) async* {
  final chunkSize = reply.chunkSize ?? reply.payload.length;
  for (var offset = 0; offset < reply.payload.length; offset += chunkSize) {
    if (reply.chunkDelay > Duration.zero) {
      await Future<void>.delayed(reply.chunkDelay);
    }

    final end = (offset + chunkSize).clamp(0, reply.payload.length);
    yield Uint8List.sublistView(reply.payload, offset, end);
  }
}

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

      final dl = ModelDownloader(dio: _dioWith(_DownloadReply(payload)));
      var lastReceived = -1;
      int? lastTotal;
      await dl.download(
        file: ModelFile(
          localName: 'thing.bin',
          url: 'https://models.test/thing.bin',
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

      await ModelDownloader(dio: _dioWith(_DownloadReply(payload))).download(
        file: ModelFile(
          localName: 'verified.bin',
          url: 'https://models.test/verified.bin',
          sha256: expected,
        ),
        destDir: tmp.path,
      );
      expect(File(p.join(tmp.path, 'verified.bin')).existsSync(), isTrue);
    });

    test('sha256 mismatch: throws + deletes partial', () async {
      final payload = _bytes(2048, seed: 9);

      await expectLater(
        () => ModelDownloader(dio: _dioWith(_DownloadReply(payload))).download(
          file: ModelFile(
            localName: 'bad.bin',
            url: 'https://models.test/bad.bin',
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
      final payload = _bytes(1024 * 1024);
      final cancel = DownloadCancellation();
      final dl = ModelDownloader(
        dio: _dioWith(
          _DownloadReply(
            payload,
            chunkSize: 64 * 1024,
            chunkDelay: const Duration(milliseconds: 100),
          ),
        ),
      );
      final fut = dl.download(
        file: const ModelFile(
          localName: 'slow.bin',
          url: 'https://models.test/slow.bin',
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

      await ModelDownloader(dio: _dioWith(_DownloadReply(newPayload))).download(
        file: ModelFile(
          localName: 'rewrite.bin',
          url: 'https://models.test/rewrite.bin',
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
