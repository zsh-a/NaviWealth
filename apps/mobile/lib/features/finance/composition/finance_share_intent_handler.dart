/// FinanceOS share-intent handling.
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifeos/share_intent.dart';
import '../ingest/data/capture_encoder.dart';
import '../ingest/data/ingest_capture_policy.dart';
import '../ingest/data/ingest_capture_source.dart';
import '../ingest/data/providers.dart';
import '../ingest/domain/ingest_models.dart';
import 'finance_route_paths.dart';

class FinanceShareIntentHandler extends DomainShareIntentHandler {
  const FinanceShareIntentHandler() : super(priority: 0);

  static const int _navigationPriority = 100;

  @override
  Future<DomainShareIntentResult?> handle(
    Ref ref,
    SharedIntentPayload payload,
  ) async {
    final source = await _toSource(payload);
    if (source == null) return null;
    await ref.read(ingestControllerProvider).ingest(source);
    return const DomainShareIntentResult(
      destinationPath: FinanceRoutes.activityIngest,
      navigationPriority: _navigationPriority,
    );
  }

  Future<IngestSource?> _toSource(SharedIntentPayload payload) async {
    final IngestCaptureOutcome outcome;
    if (payload.kind == SharedIntentKind.text ||
        payload.kind == SharedIntentKind.url) {
      outcome = ingestSourceFromTextCapture(
        text: payload.value,
        originLabel: 'share',
      );
    } else if (payload.kind == SharedIntentKind.image ||
        payload.kind == SharedIntentKind.file) {
      outcome = await xFileToIngestSource(
        XFile(payload.value),
        mimeType: payload.mimeType,
        trustedImage: payload.kind == SharedIntentKind.image,
      );
    } else {
      return null;
    }
    return switch (outcome) {
      IngestCaptureSuccess(:final source) => source,
      IngestCaptureCancelled() || IngestCaptureFailure() => null,
    };
  }
}
