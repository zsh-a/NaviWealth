/// KnowledgeOS Riverpod wiring (`docs/knowledgeos-domain.md` §3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import 'inbox_triage_repository.dart';
import 'knowledge_repository.dart';

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
