/// KnowledgeOS Riverpod wiring (`docs/knowledgeos-domain.md` §3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../ai_chat/data/providers.dart' show deviceLlmRuntimeProvider;
import 'capture_classifier.dart';
import 'inbox_triage_repository.dart';
import 'knowledge_repository.dart';
import 'llm_capture_classifier.dart';

/// Single Uuid instance shared by every KnowledgeOS writer / tool.
/// Replaces a handful of per-file `_kUuid` / `kInboxTriageUuid`
/// declarations — Uuid is stateless, no reason to hold several.
const Uuid kKnowledgeUuid = Uuid();

final knowledgeRepositoryProvider = FutureProvider<KnowledgeRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  return KnowledgeRepository(db: db, outbox: outbox);
});

final inboxTriageRepositoryProvider =
    FutureProvider<InboxTriageRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return InboxTriageRepository(db: db);
});

/// Capture classifier seam. Returns the LLM-driven classifier when a
/// device LLM profile is configured; falls back to the deterministic
/// heuristic otherwise. The LLM classifier internally degrades to the
/// same heuristic on any per-call failure (network / timeout / parse),
/// so call sites never observe an exception out of `classify`.
///
/// CaptureSheet + `propose_capture` tool both read this provider, so
/// the AI-native upgrade UX and the AI tool surface share one
/// classifier instance — matching the §4 "tools mirror UI" contract.
final captureClassifierProvider = Provider<CaptureClassifier>((ref) {
  final runtime = ref.watch(deviceLlmRuntimeProvider);
  if (runtime == null) {
    return const HeuristicCaptureClassifier();
  }
  return LlmCaptureClassifier(client: runtime.client);
});
