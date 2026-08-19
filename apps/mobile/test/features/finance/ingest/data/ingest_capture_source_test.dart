import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_source.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

void main() {
  group('capture type resolution', () {
    test(
      'rejects a supported MIME when a known extension is unsupported',
      () async {
        final file = _FakeCaptureFile(
          name: 'statement.docx',
          mimeType: 'application/pdf',
          chunks: [_oneByte],
        );

        final outcome = await readIngestCaptureFile(file);

        expect(_failureCode(outcome), IngestCaptureFailureCode.unsupported);
        expect(file.lengthCalls, 0);
        expect(file.openCalls, 0);
      },
    );

    test('uses MIME for extensionless files', () async {
      final outcome = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'shared-statement',
          mimeType: 'application/pdf; charset=binary',
          lengths: [1, 1],
          chunks: [_oneByte],
        ),
      );

      expect(_success(outcome).kind, IngestSourceKind.statementPdf);
    });

    test('recognises XLSX by extension and standard MIME', () async {
      for (final file in <_FakeCaptureFile>[
        _FakeCaptureFile(
          name: 'statement.xlsx',
          lengths: [1, 1],
          chunks: [_oneByte],
        ),
        _FakeCaptureFile(
          name: 'shared-statement',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          lengths: [1, 1],
          chunks: [_oneByte],
        ),
      ]) {
        final outcome = await readIngestCaptureFile(file);

        expect(
          _failureCode(outcome),
          IngestCaptureFailureCode.unreadable,
          reason: file.name,
        );
        expect(file.openCalls, 1, reason: file.name);
      }
    });

    test(
      'only trusted image lanes may default an unknown file to JPEG',
      () async {
        final generic = await readIngestCaptureFile(
          _FakeCaptureFile(name: 'unknown', chunks: [_oneByte]),
        );
        final trusted = await readIngestCaptureFile(
          _FakeCaptureFile(
            name: 'camera-capture',
            lengths: [1, 1],
            chunks: [_oneByte],
          ),
          trustedImage: true,
        );

        expect(_failureCode(generic), IngestCaptureFailureCode.unsupported);
        expect(_success(trusted).kind, IngestSourceKind.receiptImage);
        expect(_success(trusted).mime, 'image/jpeg');
      },
    );
  });

  group('bounded capture reader', () {
    test('known oversize rejects before opening the stream', () async {
      final file = _FakeCaptureFile(
        name: 'large.csv',
        lengths: [IngestCaptureLimits.statementTextBytes + 1],
        chunks: [_oneByte],
      );

      final outcome = await readIngestCaptureFile(file);

      expect(_failureCode(outcome), IngestCaptureFailureCode.tooLarge);
      expect(file.openCalls, 0);
    });

    test('unknown length accepts the exact PDF limit', () async {
      const limit = IngestCaptureLimits.statementPdfBytes;
      final outcome = await readIngestCaptureFile(
        _FakeCaptureFile(name: 'statement.pdf', chunks: [Uint8List(limit)]),
      );

      expect(_success(outcome).kind, IngestSourceKind.statementPdf);
    });

    test('rejects the first byte beyond each lane budget', () async {
      for (final entry in <(String, int)>[
        ('statement.csv', IngestCaptureLimits.statementTextBytes),
        ('statement.xlsx', IngestCaptureLimits.statementWorkbookBytes),
        ('receipt.jpg', IngestCaptureLimits.receiptImageBytes),
        ('statement.pdf', IngestCaptureLimits.statementPdfBytes),
      ]) {
        final file = _FakeCaptureFile(
          name: entry.$1,
          chunks: [Uint8List(entry.$2), _oneByte],
        );

        final outcome = await readIngestCaptureFile(file);

        expect(
          _failureCode(outcome),
          IngestCaptureFailureCode.tooLarge,
          reason: entry.$1,
        );
        expect(file.yieldedChunks, 2, reason: entry.$1);
      }
    });

    test(
      'does not retain or request chunks after a single oversized chunk',
      () async {
        final file = _FakeCaptureFile(
          name: 'receipt.png',
          chunks: [
            Uint8List(IngestCaptureLimits.receiptImageBytes + 1),
            _oneByte,
          ],
        );

        final outcome = await readIngestCaptureFile(file);

        expect(_failureCode(outcome), IngestCaptureFailureCode.tooLarge);
        expect(file.yieldedChunks, 1);
      },
    );

    test('treats empty streams as empty captures', () async {
      final outcome = await readIngestCaptureFile(
        _FakeCaptureFile(name: 'empty.txt'),
      );

      expect(_failureCode(outcome), IngestCaptureFailureCode.empty);
    });

    test('maps length and stream errors to unreadable', () async {
      final lengthError = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'broken.pdf',
          lengthError: StateError('length unavailable'),
        ),
      );
      final streamError = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'broken.pdf',
          streamError: StateError('read unavailable'),
        ),
      );

      expect(_failureCode(lengthError), IngestCaptureFailureCode.unreadable);
      expect(_failureCode(streamError), IngestCaptureFailureCode.unreadable);
    });

    test('rejects pre-read and post-read length mismatches', () async {
      final changed = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'changed.pdf',
          lengths: [1, 2],
          chunks: [_oneByte],
        ),
      );
      final inaccurate = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'inaccurate.pdf',
          lengths: [2, 2],
          chunks: [_oneByte],
        ),
      );

      expect(_failureCode(changed), IngestCaptureFailureCode.unreadable);
      expect(_failureCode(inaccurate), IngestCaptureFailureCode.unreadable);
    });

    test('post-read length above the budget wins as too large', () async {
      final outcome = await readIngestCaptureFile(
        _FakeCaptureFile(
          name: 'changed.pdf',
          lengths: [1, IngestCaptureLimits.statementPdfBytes + 1],
          chunks: [_oneByte],
        ),
      );

      expect(_failureCode(outcome), IngestCaptureFailureCode.tooLarge);
    });

    test(
      'pathless PlatformFile returns unreadable instead of throwing',
      () async {
        final outcome = await platformFileToIngestSource(
          _UnreadablePlatformFile(),
        );

        expect(_failureCode(outcome), IngestCaptureFailureCode.unreadable);
      },
    );
  });
}

final Uint8List _oneByte = Uint8List.fromList(const [1]);

final class _UnreadablePlatformFile extends PlatformFile {
  @override
  final String name = 'saf.pdf';

  @override
  final Uri uri = Uri.parse('content://naviwealth/saf.pdf');

  @override
  XFile get xFile => throw StateError('xFile unavailable');

  @override
  Future<int> length() async => 1;

  @override
  Future<Uint8List> readAsBytes() async {
    throw StateError('bytes unavailable');
  }

  @override
  Stream<Uint8List> readAsByteStream() {
    return Stream<Uint8List>.error(StateError('stream unavailable'));
  }
}

IngestCaptureFailureCode _failureCode(IngestCaptureOutcome outcome) =>
    (outcome as IngestCaptureFailure).code;

IngestSource _success(IngestCaptureOutcome outcome) =>
    (outcome as IngestCaptureSuccess).source;

final class _FakeCaptureFile implements IngestCaptureFile {
  _FakeCaptureFile({
    required this.name,
    this.mimeType,
    List<int?> lengths = const [null],
    this.chunks = const [],
    this.lengthError,
    this.streamError,
  }) : _lengths = lengths;

  @override
  final String name;

  @override
  final String? mimeType;

  final List<int?> _lengths;
  final List<List<int>> chunks;
  final Object? lengthError;
  final Object? streamError;
  int lengthCalls = 0;
  int openCalls = 0;
  int yieldedChunks = 0;

  @override
  Future<int?> length() async {
    lengthCalls++;
    if (lengthError case final error?) throw error;
    final index = lengthCalls <= _lengths.length
        ? lengthCalls - 1
        : _lengths.length - 1;
    return _lengths[index];
  }

  @override
  Stream<List<int>> openRead() async* {
    openCalls++;
    if (streamError case final error?) throw error;
    for (final chunk in chunks) {
      yieldedChunks++;
      yield chunk;
    }
  }
}
