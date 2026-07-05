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
  });

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
  }) => _mergeKnowledgeNotes(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
    mergedTitle: mergedTitle,
    mergedBody: mergedBody,
  );

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
  }) => _mergeKnowledgeConcepts(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
    mergedName: mergedName,
    mergedSummary: mergedSummary,
  );

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
  }) => _linkKnowledgeConcepts(this, a: a, b: b, stamp: stamp);

  /// Merge [duplicates] into [primary] principle (§15.3 P1). Tombstones each
  /// duplicate (`mergedIntoId = primary.id`) and **re-points inbound refs**:
  /// any live Decision citing a duplicate in `principleIds` now cites the
  /// survivor. Principles carry no list fields to union, so the survivor's
  /// own statement/rationale stand. One transaction. Returns the survivor.
  Future<KnowledgePrinciple> mergePrinciples({
    required KnowledgePrinciple primary,
    required List<KnowledgePrinciple> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) => _mergeKnowledgePrinciples(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
  );

  /// Merge [duplicates] into [primary] assumption (§15.3 P1). Unions evidence
  /// ids onto the survivor, tombstones each duplicate, and re-points inbound
  /// refs: live Decisions' `assumptionIds` and Experiments'
  /// `targetAssumptionId` that pointed at a duplicate now point at the
  /// survivor. One transaction. Returns the survivor.
  Future<KnowledgeAssumption> mergeAssumptions({
    required KnowledgeAssumption primary,
    required List<KnowledgeAssumption> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) => _mergeKnowledgeAssumptions(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
  );

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
  }) => _mergeKnowledgeDecisions(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
  );

  /// Merge [duplicates] into [primary] experiment (§15.3 P1). Experiments
  /// carry no inbound id references, so this only unions metrics onto the
  /// survivor and tombstones each duplicate. One transaction. Returns the
  /// survivor.
  Future<KnowledgeExperiment> mergeExperiments({
    required KnowledgeExperiment primary,
    required List<KnowledgeExperiment> duplicates,
    required Future<SyncMeta> Function() stamp,
  }) => _mergeKnowledgeExperiments(
    this,
    primary: primary,
    duplicates: duplicates,
    stamp: stamp,
  );
}
