import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/lifeos/share_intent.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/composition/finance_share_intent_handler.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_feedback.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

final _handleShareProvider =
    FutureProvider.family<DomainShareIntentResult?, SharedIntentPayload>(
      (ref, payload) => const FinanceShareIntentHandler().handle(ref, payload),
    );

void main() {
  test('successful shared text is trimmed, ingested, and routed', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    final result = await fixture.handle(
      const SharedIntentPayload(
        kind: SharedIntentKind.text,
        value: '  statement row  ',
      ),
    );

    expect(result!.destinationPath, FinanceRoutes.activityIngest);
    expect(fixture.controller.sources.single.payload, 'statement row');
    expect(fixture.feedback, isEmpty);
  });

  test('unsupported file falls through without reading or routing', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    final result = await fixture.handle(
      const SharedIntentPayload(
        kind: SharedIntentKind.file,
        value: '/path/that/does/not/exist/report.docx',
      ),
    );

    expect(result, isNull);
    expect(fixture.controller.sources, isEmpty);
    expect(fixture.feedback, isEmpty);
  });

  test('multiple recognized text failures queue without overwriting', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    final tooLong = await fixture.handle(
      SharedIntentPayload(
        kind: SharedIntentKind.text,
        value: ''.padRight(IngestCaptureLimits.textCodeUnits + 1, 'a'),
      ),
    );
    final empty = await fixture.handle(
      const SharedIntentPayload(kind: SharedIntentKind.text, value: '   '),
    );

    expect(tooLong!.destinationPath, FinanceRoutes.activityIngest);
    expect(empty!.destinationPath, FinanceRoutes.activityIngest);
    expect(fixture.controller.sources, isEmpty);
    expect(fixture.feedback.map((event) => event.id), [1, 2]);
    expect(
      fixture.feedback.map(
        (event) =>
            (event.feedback as IngestCaptureFailureFeedback).failure.code,
      ),
      [IngestCaptureFailureCode.textTooLong, IngestCaptureFailureCode.empty],
    );
  });

  test(
    'oversized shared image is owned by Finance but never ingested',
    () async {
      final directory = await Directory.systemTemp.createTemp('navi-share-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/large.jpg');
      await file.writeAsBytes(
        Uint8List(IngestCaptureLimits.receiptImageBytes + 1),
        flush: true,
      );
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      final result = await fixture.handle(
        SharedIntentPayload(kind: SharedIntentKind.image, value: file.path),
      );

      expect(result!.destinationPath, FinanceRoutes.activityIngest);
      expect(fixture.controller.sources, isEmpty);
      expect(
        (fixture.feedback.single.feedback as IngestCaptureFailureFeedback)
            .failure
            .code,
        IngestCaptureFailureCode.tooLarge,
      );
    },
  );

  test('MIME routes a readable extensionless shared file', () async {
    final directory = await Directory.systemTemp.createTemp('navi-share-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/statement');
    await file.writeAsBytes(const [1, 2, 3], flush: true);
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    final result = await fixture.handle(
      SharedIntentPayload(
        kind: SharedIntentKind.file,
        value: file.path,
        mimeType: 'application/pdf',
      ),
    );

    expect(result!.destinationPath, FinanceRoutes.activityIngest);
    expect(
      fixture.controller.sources.single.kind,
      IngestSourceKind.statementPdf,
    );
  });

  test('parser rejection is queued and still routes to review', () async {
    final fixture = _Fixture(
      result: const IngestResult(drafts: [], rejectedReason: 'blocked'),
    );
    addTearDown(fixture.dispose);

    final result = await fixture.handle(
      const SharedIntentPayload(kind: SharedIntentKind.text, value: 'row'),
    );

    expect(result!.destinationPath, FinanceRoutes.activityIngest);
    expect(
      (fixture.feedback.single.feedback as IngestProcessingFailureFeedback)
          .code,
      IngestProcessingFailureCode.rejected,
    );
  });

  test(
    'unexpected parser exception is queued and does not lose navigation',
    () async {
      final fixture = _Fixture(throws: true);
      addTearDown(fixture.dispose);

      final result = await fixture.handle(
        const SharedIntentPayload(kind: SharedIntentKind.text, value: 'row'),
      );

      expect(result!.destinationPath, FinanceRoutes.activityIngest);
      expect(
        (fixture.feedback.single.feedback as IngestProcessingFailureFeedback)
            .code,
        IngestProcessingFailureCode.failed,
      );
    },
  );
}

class _Fixture {
  _Fixture({
    IngestResult result = const IngestResult(drafts: []),
    bool throws = false,
  }) {
    container = ProviderContainer(
      overrides: [
        ingestControllerProvider.overrideWith(
          (ref) => _FakeIngestController(ref, result: result, throws: throws),
        ),
      ],
    );
    controller =
        container.read(ingestControllerProvider) as _FakeIngestController;
  }

  late final ProviderContainer container;
  late final _FakeIngestController controller;

  List<IngestCaptureFeedbackEvent> get feedback =>
      container.read(ingestCaptureFeedbackQueueProvider);

  Future<DomainShareIntentResult?> handle(SharedIntentPayload payload) =>
      container.read(_handleShareProvider(payload).future);

  void dispose() => container.dispose();
}

class _FakeIngestController extends IngestController {
  _FakeIngestController(
    super.ref, {
    required this.result,
    required this.throws,
  });

  final IngestResult result;
  final bool throws;
  final List<IngestSource> sources = [];

  @override
  Future<IngestResult> ingest(IngestSource source) async {
    sources.add(source);
    if (throws) throw StateError('ingest failed');
    return result;
  }
}
