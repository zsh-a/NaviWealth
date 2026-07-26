/// KnowledgeOS Inbox triage store (`docs/domains/knowledgeos-domain.md` §5 + §7).
///
/// Wraps the local-only `knowledge_inbox_triage` side-table — one row
/// per Note that the [InboxTriageAgent] has looked at, with the
/// proposal envelopes it emitted held as JSON. The side-table is
/// **never-sync** (DDL in `core/persistence/local_only_tables.dart`),
/// so this repository never enqueues to the outbox; proposals are
/// device-derived and rebuilt from the note on demand if needed.
///
/// The envelope shape mirrors the cross-domain `propose_*` contract
/// (matches `ProposeConceptLinkTool`): `{kind, summary_zh, payload}`
/// plus a per-proposal `status` we carry in JSON because the Review
/// tab needs to mark individual items accepted / dismissed.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../core/persistence/app_database.dart';
import '../domain/knowledge_models.dart';

String knowledgeNoteTriageFingerprint(KnowledgeNote note) {
  final normalized = jsonEncode(<String, Object?>{
    'title': note.title.trim(),
    'body_md': note.bodyMd.trim(),
    'source_url': note.sourceUrl?.trim(),
    'tags': note.tags.map((tag) => tag.trim().toLowerCase()).toList()..sort(),
    'project_tag': note.projectTag?.trim(),
  });
  return sha256.convert(utf8.encode(normalized)).toString();
}

/// What an inbox proposal recommends. Matches §4 / §7 trio.
enum InboxProposalKind {
  classification,
  tags,
  linkToDecision;

  String get wire => switch (this) {
    classification => 'classification',
    tags => 'tags',
    linkToDecision => 'link_to_decision',
  };

  static InboxProposalKind parse(String s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return InboxProposalKind.classification;
  }
}

/// Per-proposal resolution. `dismissed` means the user said "no thanks"
/// — the agent must not re-propose the same kind for the same note.
enum InboxProposalStatus {
  pending,
  accepted,
  dismissed,
  superseded;

  String get wire => name;

  static InboxProposalStatus parse(String s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return InboxProposalStatus.pending;
  }
}

/// Optional user feedback on a pending suggestion. It does not resolve the
/// proposal; it is local signal for future triage quality and UX inspection.
enum InboxProposalFeedback {
  positive,
  negative;

  String get wire => switch (this) {
    positive => 'positive',
    negative => 'negative',
  };

  static InboxProposalFeedback? parse(String? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// One envelope as stored inside the `proposals_json` array. Mirrors
/// the `ProposalEnvelope` shape returned by `queue_inbox_*` tools.
class InboxProposal {
  InboxProposal({
    required this.kind,
    required this.summaryZh,
    required this.payload,
    required this.status,
    DateTime? resolvedAt,
    DateTime? snoozedUntil,
    this.feedback,
  }) : resolvedAt = resolvedAt?.toUtc(),
       snoozedUntil = snoozedUntil?.toUtc();

  final InboxProposalKind kind;
  final String summaryZh;
  final Map<String, Object?> payload;
  final InboxProposalStatus status;
  final DateTime? resolvedAt;
  final DateTime? snoozedUntil;
  final InboxProposalFeedback? feedback;

  bool isVisiblePending(DateTime now) =>
      status == InboxProposalStatus.pending &&
      (snoozedUntil == null || !snoozedUntil!.isAfter(now.toUtc()));

  InboxProposal copyWith({
    InboxProposalStatus? status,
    DateTime? resolvedAt,
    DateTime? snoozedUntil,
    InboxProposalFeedback? feedback,
  }) => InboxProposal(
    kind: kind,
    summaryZh: summaryZh,
    payload: payload,
    status: status ?? this.status,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    feedback: feedback ?? this.feedback,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wire,
    'summary_zh': summaryZh,
    'payload': payload,
    'status': status.wire,
    if (resolvedAt != null) 'resolved_at': resolvedAt!.millisecondsSinceEpoch,
    if (snoozedUntil != null)
      'snoozed_until': snoozedUntil!.millisecondsSinceEpoch,
    if (feedback != null) 'feedback': feedback!.wire,
  };

  static InboxProposal fromJson(Map<String, Object?> j) {
    final payload = j['payload'];
    final resolvedAt = j['resolved_at'];
    final snoozedUntil = j['snoozed_until'];
    return InboxProposal(
      kind: InboxProposalKind.parse((j['kind'] as String?) ?? ''),
      summaryZh: (j['summary_zh'] as String?) ?? '',
      payload: payload is Map
          ? payload.map((k, v) => MapEntry(k.toString(), v))
          : const <String, Object?>{},
      status: InboxProposalStatus.parse((j['status'] as String?) ?? ''),
      resolvedAt: resolvedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(resolvedAt, isUtc: true)
          : null,
      snoozedUntil: snoozedUntil is int
          ? DateTime.fromMillisecondsSinceEpoch(snoozedUntil, isUtc: true)
          : null,
      feedback: InboxProposalFeedback.parse(j['feedback'] as String?),
    );
  }
}

/// One row in `knowledge_inbox_triage`.
class InboxTriageRecord {
  InboxTriageRecord({
    required this.noteId,
    required this.ownerUserId,
    required this.sourceFingerprint,
    required this.lastTriagedAt,
    required this.proposals,
  });

  final String noteId;
  final String ownerUserId;
  final String sourceFingerprint;
  final DateTime lastTriagedAt;
  final List<InboxProposal> proposals;

  Iterable<InboxProposal> pendingAt(DateTime now) =>
      proposals.where((p) => p.isVisiblePending(now));

  Iterable<InboxProposal> get pending => pendingAt(DateTime.now().toUtc());

  /// The agent must not re-propose a kind that the user has already
  /// dismissed for this note (§7 "dismissed 提议不再重提").
  Set<InboxProposalKind> get dismissedKinds => proposals
      .where((p) => p.status == InboxProposalStatus.dismissed)
      .map((p) => p.kind)
      .toSet();
}

class InboxTriageRepository {
  InboxTriageRepository({required AppDatabase db}) : _db = db;
  final AppDatabase _db;

  /// Single-note lookup (Review tab tile + agent skip check).
  Future<InboxTriageRecord?> findForNote(String noteId) async {
    final row = await _db
        .customSelect(
          'SELECT note_id, owner_user_id, source_fingerprint, '
          'last_triaged_at, proposals_json '
          'FROM knowledge_inbox_triage WHERE note_id = ?',
          variables: [Variable.withString(noteId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToRecord(row.data);
  }

  /// Pending-proposal feed for the Review tab "AI 建议" card. Returns
  /// records that still have at least one envelope in `pending` state,
  /// most recent first.
  Future<List<InboxTriageRecord>> listPending({
    required String ownerUserId,
    int limit = 20,
  }) async {
    if (limit <= 0) return const <InboxTriageRecord>[];
    final now = DateTime.now().toUtc();
    final rows = await _db
        .customSelect(
          'SELECT note_id, owner_user_id, source_fingerprint, '
          'last_triaged_at, proposals_json '
          'FROM knowledge_inbox_triage WHERE owner_user_id = ? '
          'ORDER BY last_triaged_at DESC LIMIT ?',
          variables: [
            Variable.withString(ownerUserId),
            Variable.withInt(limit * 3),
          ],
        )
        .get();
    final out = <InboxTriageRecord>[];
    for (final row in rows) {
      final rec = _rowToRecord(row.data);
      if (rec.pendingAt(now).isEmpty) continue;
      out.add(rec);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Upsert a triage row. Overwrites `proposals_json` wholesale — the
  /// caller decides whether to merge with existing proposals (agent
  /// does merge to honour dismissed kinds; UI never touches this path).
  Future<void> upsert(InboxTriageRecord rec) async {
    final json = jsonEncode(rec.proposals.map((p) => p.toJson()).toList());
    await _db.customStatement(
      'INSERT OR REPLACE INTO knowledge_inbox_triage ('
      '  note_id, owner_user_id, source_fingerprint, last_triaged_at, '
      '  proposals_json'
      ') VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        rec.noteId,
        rec.ownerUserId,
        rec.sourceFingerprint,
        rec.lastTriagedAt.toUtc().millisecondsSinceEpoch,
        json,
      ],
    );
  }

  /// Mark one proposal accepted or dismissed. Idempotent — re-resolving
  /// is a no-op rather than an error so the UI doesn't have to disable
  /// buttons across rebuilds.
  Future<void> resolve({
    required String noteId,
    required InboxProposalKind kind,
    required InboxProposalStatus status,
    DateTime? at,
  }) async {
    final existing = await findForNote(noteId);
    if (existing == null) return;
    final now = (at ?? DateTime.now().toUtc()).toUtc();
    final updated = existing.proposals
        .map(
          (p) =>
              p.kind == kind ? p.copyWith(status: status, resolvedAt: now) : p,
        )
        .toList(growable: false);
    await upsert(
      InboxTriageRecord(
        noteId: existing.noteId,
        ownerUserId: existing.ownerUserId,
        sourceFingerprint: existing.sourceFingerprint,
        lastTriagedAt: existing.lastTriagedAt,
        proposals: updated,
      ),
    );
  }

  Future<void> supersedePending({
    required String noteId,
    required Set<InboxProposalKind> kinds,
    DateTime? at,
  }) async {
    final existing = await findForNote(noteId);
    if (existing == null || kinds.isEmpty) return;
    final now = (at ?? DateTime.now().toUtc()).toUtc();
    final updated = existing.proposals
        .map(
          (proposal) =>
              proposal.status == InboxProposalStatus.pending &&
                  kinds.contains(proposal.kind)
              ? proposal.copyWith(
                  status: InboxProposalStatus.superseded,
                  resolvedAt: now,
                )
              : proposal,
        )
        .toList(growable: false);
    await upsert(
      InboxTriageRecord(
        noteId: existing.noteId,
        ownerUserId: existing.ownerUserId,
        sourceFingerprint: existing.sourceFingerprint,
        lastTriagedAt: existing.lastTriagedAt,
        proposals: updated,
      ),
    );
  }

  /// Hide a still-pending proposal until [until]. The status remains
  /// pending, so it returns to the Review tab automatically after the
  /// snooze expires.
  Future<void> snooze({
    required String noteId,
    required InboxProposalKind kind,
    required DateTime until,
  }) => _updateProposal(
    noteId: noteId,
    kind: kind,
    update: (p) => p.copyWith(snoozedUntil: until.toUtc()),
  );

  /// Persist lightweight quality feedback without resolving the proposal.
  Future<void> recordFeedback({
    required String noteId,
    required InboxProposalKind kind,
    required InboxProposalFeedback feedback,
  }) => _updateProposal(
    noteId: noteId,
    kind: kind,
    update: (p) => p.copyWith(feedback: feedback),
  );

  Future<void> _updateProposal({
    required String noteId,
    required InboxProposalKind kind,
    required InboxProposal Function(InboxProposal) update,
  }) async {
    final existing = await findForNote(noteId);
    if (existing == null) return;
    final updated = existing.proposals
        .map((p) => p.kind == kind ? update(p) : p)
        .toList(growable: false);
    await upsert(
      InboxTriageRecord(
        noteId: existing.noteId,
        ownerUserId: existing.ownerUserId,
        sourceFingerprint: existing.sourceFingerprint,
        lastTriagedAt: existing.lastTriagedAt,
        proposals: updated,
      ),
    );
  }

  /// Note ids that already have a triage row — used by the agent to
  /// skip already-proposed notes without per-note point lookups.
  Future<Map<String, String>> triagedNoteFingerprints({
    required String ownerUserId,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT note_id, source_fingerprint FROM knowledge_inbox_triage '
          'WHERE owner_user_id = ?',
          variables: [Variable.withString(ownerUserId)],
        )
        .get();
    return <String, String>{
      for (final row in rows)
        row.data['note_id'] as String: row.data['source_fingerprint'] as String,
    };
  }

  InboxTriageRecord _rowToRecord(Map<String, Object?> r) {
    final raw = (r['proposals_json'] as String?) ?? '[]';
    final decoded = jsonDecode(raw);
    final proposals = decoded is List
        ? decoded
              .whereType<Map<String, Object?>>()
              .map(InboxProposal.fromJson)
              .toList(growable: false)
        : const <InboxProposal>[];
    return InboxTriageRecord(
      noteId: r['note_id'] as String,
      ownerUserId: r['owner_user_id'] as String,
      sourceFingerprint: r['source_fingerprint'] as String,
      lastTriagedAt: DateTime.fromMillisecondsSinceEpoch(
        r['last_triaged_at'] as int,
        isUtc: true,
      ),
      proposals: proposals,
    );
  }
}
