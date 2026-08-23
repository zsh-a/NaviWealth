part of 'knowledge_object_memory_indexers.dart';

Future<void> _reindexNotes(
  MemoryRuntime runtime,
  List<KnowledgeNote> notes, {
  required String ownerUserId,
  required String untitled,
}) async {
  final now = DateTime.now().toUtc();
  await _forgetMissingSourceIds(
    runtime,
    ownerUserId: ownerUserId,
    source: kKnowledgeNoteMemorySource,
    liveSourceIds: {for (final n in notes) n.id},
  );
  for (final n in notes) {
    final id = '$kKnowledgeNoteMemorySource:episodic:${n.id}';
    // Attachment references carry no semantic signal — index the compact
    // marker form so `attachment://` ids never reach embeddings.
    final bodyForIndex = knowledgeMarkdownWithoutAttachments(n.bodyMd);
    final summary = n.bodyMd.isEmpty
        ? n.title
        : '${n.title.isEmpty ? "(untitled)" : n.title}: ${_truncate(bodyForIndex)}';
    await recordKnowledgeStateEvent(
      runtime,
      ownerUserId: ownerUserId,
      kind: 'knowledge_note_state',
      sourceFamily: kKnowledgeNoteEventSourceFamily,
      rowId: n.id,
      fingerprint: n.sync.hlc.toString(),
      occurredAt: n.sync.updatedAt,
      observedAt: now,
      title: n.title.isEmpty ? untitled : n.title,
      summary: summary,
      facts: <String, Object?>{
        'tags': n.tags,
        if (n.projectTag != null) 'project_tag': n.projectTag,
        if (n.sourceUrl != null) 'source_url': n.sourceUrl,
        'promoted': n.isPromoted,
      },
      entities: <String>{
        'knowledge_note',
        n.id,
        ...n.tags.map((tag) => 'tag:$tag'),
      },
      importance: 0.5,
      confidence: 1,
    );
    await runtime.remember(
      MemoryRecord(
        id: id,
        kind: MemoryKind.episodic,
        role: MemoryRole.episode,
        authority: EvidenceAuthority.sourceFact,
        ownerUserId: ownerUserId,
        scope: '*',
        source: kKnowledgeNoteMemorySource,
        sourceId: n.id,
        title: n.title.isEmpty ? untitled : n.title,
        summary: summary,
        payload: <String, Object?>{
          'body_md': bodyForIndex,
          'tags': n.tags,
          if (n.projectTag != null) 'project_tag': n.projectTag,
          if (n.sourceUrl != null) 'source_url': n.sourceUrl,
        },
        entities: <String>{
          'knowledge_note',
          n.id,
          ...n.tags.map((t) => 'tag:$t'),
        },
        importance: 0.5,
        confidence: 0.85,
        validFrom: n.createdAt.toUtc(),
        createdAt: n.createdAt.toUtc(),
        updatedAt: now,
      ),
    );
  }
}

final knowledgeNoteMemoryIndexerProvider = Provider<void>((ref) {
  final l10n = _knowledgeIndexerL10n(ref.watch(localeProvider));
  subscribeKnowledgeIndexer<KnowledgeNote>(
    ref,
    streamOf: (r, uid) => r.watchNotes(ownerUserId: uid, limit: 200),
    reindex: (runtime, notes, {required ownerUserId}) => _reindexNotes(
      runtime,
      notes,
      ownerUserId: ownerUserId,
      untitled: l10n.knowledgeUntitled,
    ),
  );
});

AppLocalizations _knowledgeIndexerL10n(Locale? preferred) {
  final locale = preferred ?? PlatformDispatcher.instance.locale;
  final supported = locale.languageCode == 'zh'
      ? const Locale('zh')
      : const Locale('en');
  return lookupAppLocalizations(supported);
}
