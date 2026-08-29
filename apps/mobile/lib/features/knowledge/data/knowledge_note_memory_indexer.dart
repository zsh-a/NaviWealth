/// Knowledge note to Memory Runtime indexer.
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/context_evidence.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_memory_indexer_support.dart';

Future<void> _reindexNotes(
  MemoryRuntime runtime,
  List<KnowledgeNote> notes, {
  required String ownerUserId,
  required String untitled,
}) async {
  final now = DateTime.now().toUtc();
  await runtime.forgetSourceExcept(
    ownerUserId: ownerUserId,
    source: kKnowledgeNoteMemorySource,
    keepSourceIds: {for (final note in notes) note.id},
  );
  for (final note in notes) {
    final body = note.bodyMd;
    final title = note.title.isEmpty ? untitled : note.title;
    final summary = body.isEmpty ? title : '$title: ${knowledgeExcerpt(body)}';
    await recordKnowledgeStateEvent(
      runtime,
      ownerUserId: ownerUserId,
      kind: 'knowledge_note_state',
      sourceFamily: kKnowledgeNoteEventSourceFamily,
      rowId: note.id,
      fingerprint: note.sync.hlc.toString(),
      occurredAt: note.sync.updatedAt,
      observedAt: now,
      title: title,
      summary: summary,
      facts: <String, Object?>{
        'tags': note.tags,
        if (note.sourceUrl != null) 'source_url': note.sourceUrl,
      },
      entities: <String>{
        'knowledge_note',
        note.id,
        ...note.tags.map((tag) => 'tag:$tag'),
      },
      importance: 0.5,
    );
    await runtime.remember(
      MemoryRecord(
        id: '$kKnowledgeNoteMemorySource:episodic:${note.id}',
        kind: MemoryKind.episodic,
        role: MemoryRole.episode,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeNoteMemorySource,
        sourceId: note.id,
        title: title,
        summary: summary,
        payload: <String, Object?>{
          'body_md': body,
          'tags': note.tags,
          if (note.sourceUrl != null) 'source_url': note.sourceUrl,
        },
        entities: <String>{
          'knowledge_note',
          note.id,
          ...note.tags.map((tag) => 'tag:$tag'),
        },
        importance: 0.5,
        confidence: 0.85,
        validFrom: note.createdAt.toUtc(),
        createdAt: note.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeNoteMemoryIndexerProvider = Provider<void>((ref) {
  final l10n = _l10n(ref.watch(localeProvider));
  subscribeKnowledgeIndexer<KnowledgeNote>(
    ref,
    streamOf: (repository, userId) =>
        repository.watchNotes(ownerUserId: userId, limit: 200),
    reindex: (runtime, notes, {required ownerUserId}) => _reindexNotes(
      runtime,
      notes,
      ownerUserId: ownerUserId,
      untitled: l10n.knowledgeUntitled,
    ),
  );
});

AppLocalizations _l10n(Locale? preferred) {
  final locale = preferred ?? PlatformDispatcher.instance.locale;
  return lookupAppLocalizations(
    locale.languageCode == 'zh' ? const Locale('zh') : const Locale('en'),
  );
}
