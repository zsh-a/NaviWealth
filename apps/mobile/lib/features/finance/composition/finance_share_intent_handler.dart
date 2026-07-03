/// FinanceOS share-intent handling.
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifeos/share_intent.dart';
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
    if (payload.kind == SharedIntentKind.text ||
        payload.kind == SharedIntentKind.url) {
      final text = payload.value.trim();
      if (text.isEmpty) return null;
      return IngestSource(
        kind: IngestSourceKind.pasteText,
        payload: text,
        originLabel: 'share',
      );
    }
    if (payload.kind == SharedIntentKind.image ||
        payload.kind == SharedIntentKind.file) {
      return xFileToIngestSource(XFile(payload.value));
    }
    return null;
  }
}
