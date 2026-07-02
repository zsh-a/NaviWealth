part of 'knowledge_repository.dart';

// Large cap for full-table redirect scans during a merge — every live row
// referencing a duplicate must be re-pointed, so we can't page.
const int _knowledgeRepositoryFullScanLimit = 100000;

mixin KnowledgeRepositoryMerge {
  AppDatabase get _db;

  Future<void> upsertNote(KnowledgeNote note);

  Future<void> upsertPrinciple(KnowledgePrinciple p);

  Future<void> upsertAssumption(KnowledgeAssumption a);

  Future<void> upsertDecision(KnowledgeDecision d);

  Future<void> upsertConcept(KnowledgeConcept c);

  Future<void> upsertExperiment(KnowledgeExperiment e);

  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
    int offset = 0,
  });

  Future<List<KnowledgeExperiment>> listExperiments({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  });

  Future<List<KnowledgeConcept>> listConcepts({
    required String ownerUserId,
    int limit = 1000,
    int offset = 0,
  }) async {
    final q = _db.select(_db.knowledgeConcepts)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)])
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(knowledgeConceptFromRow).toList();
  }

  /// Merge [duplicates] into [primary] (`docs/domains/knowledgeos-domain.md`
  /// §15.3). Unions tags onto the survivor, optionally overrides its
  /// title/body, then tombstones each duplicate stamped with
  /// `mergedIntoId = primary.id`. [stamp] mints one fresh [SyncMeta] per
  /// touched row (so each carries its own HLC); all stamps are minted
  /// **before** the transaction opens so the factory never re-enters the
  /// DB zone. One transaction → primary-update + duplicate-tombstones land
  /// together (the two-row-update sync story in §15.3). Returns the
  /// surviving note. Notes carry no inbound id references, so there is
  /// nothing to re-point.
  Future<KnowledgeNote> mergeNotes({
    required KnowledgeNote primary,
    required List<KnowledgeNote> duplicates,
    required Future<SyncMeta> Function() stamp,
    String? mergedTitle,
    String? mergedBody,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final mergedTags = <String>{...primary.tags};
    for (final d in dups) {
      mergedTags.addAll(d.tags);
    }
    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];

    final survivor = KnowledgeNote(
      id: primary.id,
      title: (mergedTitle != null && mergedTitle.trim().isNotEmpty)
          ? mergedTitle.trim()
          : primary.title,
      bodyMd: (mergedBody != null && mergedBody.trim().isNotEmpty)
          ? mergedBody.trim()
          : primary.bodyMd,
      sourceUrl: primary.sourceUrl,
      tags: mergedTags.toList(growable: false),
      projectTag: primary.projectTag,
      createdAt: primary.createdAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertNote(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        final meta = tombMetas[i];
        await upsertNote(
          KnowledgeNote(
            id: d.id,
            title: d.title,
            bodyMd: d.bodyMd,
            sourceUrl: d.sourceUrl,
            tags: d.tags,
            projectTag: d.projectTag,
            createdAt: d.createdAt,
            mergedIntoId: primary.id,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] concept (§15.3). Beyond the note
  /// behaviour it also (a) folds each duplicate's name into the survivor's
  /// aliases so the old name still resolves, (b) unions related-concept
  /// ids, and (c) **re-points inbound links** — any other live concept
  /// whose `relatedConceptIds` referenced a duplicate now references the
  /// primary. All in one transaction. Returns the surviving concept.
  Future<KnowledgeConcept> mergeConcepts({
    required KnowledgeConcept primary,
    required List<KnowledgeConcept> duplicates,
    required Future<SyncMeta> Function() stamp,
    String? mergedName,
    String? mergedSummary,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();

    final aliases = <String>{...primary.aliases};
    final related = <String>{...primary.relatedConceptIds};
    for (final d in dups) {
      aliases.addAll(d.aliases);
      aliases.add(d.name);
      related.addAll(d.relatedConceptIds);
    }
    related.removeAll(dupIds);
    related.remove(primary.id);
    aliases.remove(primary.name);

    // Re-point inbound related links across other live concepts.
    final ownerUserId = primary.sync.ownerUserId;
    final all = await listConcepts(ownerUserId: ownerUserId);
    final repoints = <(KnowledgeConcept, List<String>)>[];
    for (final c in all) {
      if (c.id == primary.id || dupIds.contains(c.id)) continue;
      if (!c.relatedConceptIds.any(dupIds.contains)) continue;
      final next = <String>{
        for (final r in c.relatedConceptIds)
          dupIds.contains(r) ? primary.id : r,
      }..remove(c.id);
      repoints.add((c, next.toList(growable: false)));
    }

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final repointMetas = <SyncMeta>[
      for (var i = 0; i < repoints.length; i++) await stamp(),
    ];

    final survivor = KnowledgeConcept(
      id: primary.id,
      name: (mergedName != null && mergedName.trim().isNotEmpty)
          ? mergedName.trim()
          : primary.name,
      aliases: aliases.toList(growable: false),
      summaryMd: (mergedSummary != null && mergedSummary.trim().isNotEmpty)
          ? mergedSummary.trim()
          : primary.summaryMd,
      relatedConceptIds: related.toList(growable: false),
      createdAt: primary.createdAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertConcept(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        final meta = tombMetas[i];
        await upsertConcept(
          KnowledgeConcept(
            id: d.id,
            name: d.name,
            aliases: d.aliases,
            summaryMd: d.summaryMd,
            relatedConceptIds: d.relatedConceptIds,
            createdAt: d.createdAt,
            mergedIntoId: primary.id,
            sync: meta.copyWith(deletedAt: meta.updatedAt),
          ),
        );
      }
      for (var i = 0; i < repoints.length; i++) {
        final (c, next) = repoints[i];
        await upsertConcept(
          KnowledgeConcept(
            id: c.id,
            name: c.name,
            aliases: c.aliases,
            summaryMd: c.summaryMd,
            relatedConceptIds: next,
            createdAt: c.createdAt,
            mergedIntoId: c.mergedIntoId,
            sync: repointMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Create a bidirectional `[[concept]]` soft link between [a] and [b]
  /// (`docs/domains/knowledgeos-domain.md` §14.2 — the `propose_concept_link`
  /// apply path). Each concept gains the other's id in `relatedConceptIds`
  /// (idempotent — re-linking is a no-op set union). [stamp] mints one
  /// fresh [SyncMeta] per touched concept; one transaction. Returns the two
  /// updated concepts. Throws nothing on an already-linked pair — it just
  /// re-writes the same set.
  Future<(KnowledgeConcept, KnowledgeConcept)> linkConcepts({
    required KnowledgeConcept a,
    required KnowledgeConcept b,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final aMeta = await stamp();
    final bMeta = await stamp();
    final aNext = (<String>{
      ...a.relatedConceptIds,
      b.id,
    }..remove(a.id)).toList(growable: false);
    final bNext = (<String>{
      ...b.relatedConceptIds,
      a.id,
    }..remove(b.id)).toList(growable: false);
    final updatedA = KnowledgeConcept(
      id: a.id,
      name: a.name,
      aliases: a.aliases,
      summaryMd: a.summaryMd,
      relatedConceptIds: aNext,
      createdAt: a.createdAt,
      mergedIntoId: a.mergedIntoId,
      sync: aMeta,
    );
    final updatedB = KnowledgeConcept(
      id: b.id,
      name: b.name,
      aliases: b.aliases,
      summaryMd: b.summaryMd,
      relatedConceptIds: bNext,
      createdAt: b.createdAt,
      mergedIntoId: b.mergedIntoId,
      sync: bMeta,
    );
    await _db.transaction(() async {
      await upsertConcept(updatedA);
      await upsertConcept(updatedB);
    });
    return (updatedA, updatedB);
  }

  /// Merge [duplicates] into [primary] principle (§15.3 P1). Tombstones each
  /// duplicate (`mergedIntoId = primary.id`) and **re-points inbound refs**:
  /// any live Decision citing a duplicate in `principleIds` now cites the
  /// survivor. Principles carry no list fields to union, so the survivor's
  /// own statement/rationale stand. One transaction. Returns the survivor.
  Future<KnowledgePrinciple> mergePrinciples({
    required KnowledgePrinciple primary,
    required List<KnowledgePrinciple> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _knowledgeRepositoryFullScanLimit,
    );
    final affected = decisions
        .where((d) => d.principleIds.any(dupIds.contains))
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final refMetas = <SyncMeta>[
      for (var i = 0; i < affected.length; i++) await stamp(),
    ];

    final survivor = KnowledgePrinciple(
      id: primary.id,
      statement: primary.statement,
      rationaleMd: primary.rationaleMd,
      scope: primary.scope,
      status: primary.status,
      declaredAt: primary.declaredAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertPrinciple(survivor);
      for (var i = 0; i < dups.length; i++) {
        await _tombstonePrinciple(dups[i], primary.id, tombMetas[i]);
      }
      for (var i = 0; i < affected.length; i++) {
        final d = affected[i];
        await upsertDecision(
          _redirectDecision(
            d,
            principleIds: _redirectIds(d.principleIds, dupIds, primary.id),
            sync: refMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] assumption (§15.3 P1). Unions evidence
  /// ids onto the survivor, tombstones each duplicate, and re-points inbound
  /// refs: live Decisions' `assumptionIds` and Experiments'
  /// `targetAssumptionId` that pointed at a duplicate now point at the
  /// survivor. One transaction. Returns the survivor.
  Future<KnowledgeAssumption> mergeAssumptions({
    required KnowledgeAssumption primary,
    required List<KnowledgeAssumption> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final evidence = <String>{...primary.evidenceIds};
    for (final d in dups) {
      evidence.addAll(d.evidenceIds);
    }

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _knowledgeRepositoryFullScanLimit,
    );
    final affectedDecisions = decisions
        .where((d) => d.assumptionIds.any(dupIds.contains))
        .toList(growable: false);
    final experiments = await listExperiments(
      ownerUserId: ownerUserId,
      limit: _knowledgeRepositoryFullScanLimit,
    );
    final affectedExperiments = experiments
        .where((e) => dupIds.contains(e.targetAssumptionId))
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final decMetas = <SyncMeta>[
      for (var i = 0; i < affectedDecisions.length; i++) await stamp(),
    ];
    final expMetas = <SyncMeta>[
      for (var i = 0; i < affectedExperiments.length; i++) await stamp(),
    ];

    final survivor = KnowledgeAssumption(
      id: primary.id,
      statement: primary.statement,
      confidence: primary.confidence,
      scope: primary.scope,
      evidenceIds: evidence.toList(growable: false),
      status: primary.status,
      declaredAt: primary.declaredAt,
      lastVerifiedAt: primary.lastVerifiedAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertAssumption(survivor);
      for (var i = 0; i < dups.length; i++) {
        await _tombstoneAssumption(dups[i], primary.id, tombMetas[i]);
      }
      for (var i = 0; i < affectedDecisions.length; i++) {
        final d = affectedDecisions[i];
        await upsertDecision(
          _redirectDecision(
            d,
            assumptionIds: _redirectIds(d.assumptionIds, dupIds, primary.id),
            sync: decMetas[i],
          ),
        );
      }
      for (var i = 0; i < affectedExperiments.length; i++) {
        final e = affectedExperiments[i];
        await upsertExperiment(
          _redirectExperiment(
            e,
            targetAssumptionId: primary.id,
            sync: expMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] decision (§15.3 P1). Tombstones each
  /// duplicate and re-points any other live decision whose
  /// `supersededByDecisionId` pointed at a duplicate to the survivor (so the
  /// evolution chain stays intact). Distinct from a supersede edit — merge
  /// says "these rows were the same decision". One transaction. Returns the
  /// survivor.
  Future<KnowledgeDecision> mergeDecisions({
    required KnowledgeDecision primary,
    required List<KnowledgeDecision> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final dupIds = dups.map((d) => d.id).toSet();
    final ownerUserId = primary.sync.ownerUserId;

    final decisions = await listDecisions(
      ownerUserId: ownerUserId,
      limit: _knowledgeRepositoryFullScanLimit,
    );
    final affected = decisions
        .where(
          (d) =>
              d.id != primary.id &&
              !dupIds.contains(d.id) &&
              dupIds.contains(d.supersededByDecisionId),
        )
        .toList(growable: false);

    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];
    final refMetas = <SyncMeta>[
      for (var i = 0; i < affected.length; i++) await stamp(),
    ];

    final survivor = _redirectDecision(primary, sync: survivorMeta);

    await _db.transaction(() async {
      await upsertDecision(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        await upsertDecision(
          _redirectDecision(
            d,
            mergedIntoId: primary.id,
            deletedSync: tombMetas[i],
          ),
        );
      }
      for (var i = 0; i < affected.length; i++) {
        await upsertDecision(
          _redirectDecision(
            affected[i],
            supersededByDecisionId: primary.id,
            sync: refMetas[i],
          ),
        );
      }
    });
    return survivor;
  }

  /// Merge [duplicates] into [primary] experiment (§15.3 P1). Experiments
  /// carry no inbound id references, so this only unions metrics onto the
  /// survivor and tombstones each duplicate. One transaction. Returns the
  /// survivor.
  Future<KnowledgeExperiment> mergeExperiments({
    required KnowledgeExperiment primary,
    required List<KnowledgeExperiment> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) async {
    final dups = duplicates
        .where((d) => d.id != primary.id)
        .toList(growable: false);
    final metrics = <String>{...primary.metrics};
    for (final d in dups) {
      metrics.addAll(d.metrics);
    }
    final survivorMeta = await stamp();
    final tombMetas = <SyncMeta>[
      for (var i = 0; i < dups.length; i++) await stamp(),
    ];

    final survivor = KnowledgeExperiment(
      id: primary.id,
      hypothesis: primary.hypothesis,
      methodMd: primary.methodMd,
      metrics: metrics.toList(growable: false),
      status: primary.status,
      resultMd: primary.resultMd,
      conclusionMd: primary.conclusionMd,
      targetAssumptionId: primary.targetAssumptionId,
      startedAt: primary.startedAt,
      endedAt: primary.endedAt,
      sync: survivorMeta,
    );

    await _db.transaction(() async {
      await upsertExperiment(survivor);
      for (var i = 0; i < dups.length; i++) {
        final d = dups[i];
        await upsertExperiment(
          KnowledgeExperiment(
            id: d.id,
            hypothesis: d.hypothesis,
            methodMd: d.methodMd,
            metrics: d.metrics,
            status: d.status,
            resultMd: d.resultMd,
            conclusionMd: d.conclusionMd,
            targetAssumptionId: d.targetAssumptionId,
            startedAt: d.startedAt,
            endedAt: d.endedAt,
            mergedIntoId: primary.id,
            sync: tombMetas[i].copyWith(deletedAt: tombMetas[i].updatedAt),
          ),
        );
      }
    });
    return survivor;
  }

  // Replace any id in [ids] that is a duplicate with [survivorId], dedup,
  // preserving order.
  List<String> _redirectIds(
    List<String> ids,
    Set<String> dupIds,
    String survivorId,
  ) {
    final out = <String>[];
    for (final id in ids) {
      final next = dupIds.contains(id) ? survivorId : id;
      if (!out.contains(next)) out.add(next);
    }
    return out;
  }

  // Rebuild a decision row, overriding only the reference fields a merge
  // touches plus a fresh stamp. [deletedSync] tombstones the row (used for
  // the duplicate side); otherwise [sync] carries a normal update stamp.
  KnowledgeDecision _redirectDecision(
    KnowledgeDecision d, {
    List<String>? principleIds,
    List<String>? assumptionIds,
    String? supersededByDecisionId,
    String? mergedIntoId,
    SyncMeta? sync,
    SyncMeta? deletedSync,
  }) {
    final meta = deletedSync != null
        ? deletedSync.copyWith(deletedAt: deletedSync.updatedAt)
        : sync!;
    return KnowledgeDecision(
      id: d.id,
      question: d.question,
      options: d.options,
      selectedLabel: d.selectedLabel,
      rationaleMd: d.rationaleMd,
      principleIds: principleIds ?? d.principleIds,
      assumptionIds: assumptionIds ?? d.assumptionIds,
      expectedOutcome: d.expectedOutcome,
      reviewDate: d.reviewDate,
      actualOutcomeMd: d.actualOutcomeMd,
      status: d.status,
      supersededByDecisionId:
          supersededByDecisionId ?? d.supersededByDecisionId,
      contextSnapshot: d.contextSnapshot,
      decidedAt: d.decidedAt,
      mergedIntoId: mergedIntoId ?? d.mergedIntoId,
      sync: meta,
    );
  }

  KnowledgeExperiment _redirectExperiment(
    KnowledgeExperiment e, {
    required String targetAssumptionId,
    required SyncMeta sync,
  }) => KnowledgeExperiment(
    id: e.id,
    hypothesis: e.hypothesis,
    methodMd: e.methodMd,
    metrics: e.metrics,
    status: e.status,
    resultMd: e.resultMd,
    conclusionMd: e.conclusionMd,
    targetAssumptionId: targetAssumptionId,
    startedAt: e.startedAt,
    endedAt: e.endedAt,
    mergedIntoId: e.mergedIntoId,
    sync: sync,
  );

  Future<void> _tombstonePrinciple(
    KnowledgePrinciple p,
    String survivorId,
    SyncMeta meta,
  ) => upsertPrinciple(
    KnowledgePrinciple(
      id: p.id,
      statement: p.statement,
      rationaleMd: p.rationaleMd,
      scope: p.scope,
      status: p.status,
      declaredAt: p.declaredAt,
      mergedIntoId: survivorId,
      sync: meta.copyWith(deletedAt: meta.updatedAt),
    ),
  );

  Future<void> _tombstoneAssumption(
    KnowledgeAssumption a,
    String survivorId,
    SyncMeta meta,
  ) => upsertAssumption(
    KnowledgeAssumption(
      id: a.id,
      statement: a.statement,
      confidence: a.confidence,
      scope: a.scope,
      evidenceIds: a.evidenceIds,
      status: a.status,
      declaredAt: a.declaredAt,
      lastVerifiedAt: a.lastVerifiedAt,
      mergedIntoId: survivorId,
      sync: meta.copyWith(deletedAt: meta.updatedAt),
    ),
  );
}
