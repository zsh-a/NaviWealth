/// Local-only persistence for attention policy decisions.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'attention.dart';

abstract interface class AttentionDecisionStore {
  Future<void> save(AttentionDecision decision);

  Future<int> recentInterruptCount({
    required String ownerUserId,
    required DateTime since,
  });

  Future<List<AttentionDecision>> listRecent({
    required String ownerUserId,
    int limit = 100,
  });
}

class SqliteAttentionDecisionStore implements AttentionDecisionStore {
  const SqliteAttentionDecisionStore({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> save(AttentionDecision decision) {
    return _db.customStatement(
      '''
      INSERT OR REPLACE INTO attention_decisions (
        id, owner_user_id, candidate_id, agent_id, finding_fingerprint,
        level, candidate_json, reasons_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        decision.id,
        decision.ownerUserId,
        decision.candidate.id,
        decision.candidate.agentId,
        decision.candidate.findingFingerprint,
        decision.level.name,
        jsonEncode(decision.candidate.toJson()),
        jsonEncode(decision.reasons),
        decision.createdAt.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<int> recentInterruptCount({
    required String ownerUserId,
    required DateTime since,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM attention_decisions
          WHERE owner_user_id = ? AND level = 'interrupt' AND created_at >= ?
          ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withInt(since.toUtc().millisecondsSinceEpoch),
          ],
        )
        .getSingle();
    return row.read<int>('count');
  }

  @override
  Future<List<AttentionDecision>> listRecent({
    required String ownerUserId,
    int limit = 100,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM attention_decisions
          WHERE owner_user_id = ?
          ORDER BY created_at DESC
          LIMIT ?
          ''',
          variables: <Variable<Object>>[
            Variable.withString(ownerUserId),
            Variable.withInt(limit.clamp(1, 500)),
          ],
        )
        .get();
    return <AttentionDecision>[
      for (final row in rows)
        AttentionDecision(
          ownerUserId: row.read<String>('owner_user_id'),
          candidate: AttentionCandidate.fromJson(
            (jsonDecode(row.read<String>('candidate_json')) as Map)
                .cast<String, Object?>(),
          ),
          level: AttentionLevel.values.byName(row.read<String>('level')),
          reasons: (jsonDecode(row.read<String>('reasons_json')) as List)
              .whereType<String>(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
            isUtc: true,
          ),
        ),
    ];
  }
}

class AttentionDecisionService {
  const AttentionDecisionService({
    required AttentionDecisionStore store,
    this.arbiter = const AttentionArbiter(),
    this.interruptWindow = const Duration(hours: 24),
  }) : _store = store;

  final AttentionDecisionStore _store;
  final AttentionArbiter arbiter;
  final Duration interruptWindow;

  Future<AttentionDecision> evaluate({
    required String ownerUserId,
    required AttentionCandidate candidate,
    required bool novel,
    required bool suppressed,
    required bool notificationsAllowed,
    required DateTime decidedAt,
  }) async {
    final recentInterruptCount = await _store.recentInterruptCount(
      ownerUserId: ownerUserId,
      since: decidedAt.subtract(interruptWindow),
    );
    final decision = arbiter.decide(
      ownerUserId: ownerUserId,
      candidate: candidate,
      context: AttentionPolicyContext(
        novel: novel,
        suppressed: suppressed,
        notificationsAllowed: notificationsAllowed,
        recentInterruptCount: recentInterruptCount,
      ),
      decidedAt: decidedAt,
    );
    await _store.save(decision);
    return decision;
  }
}
