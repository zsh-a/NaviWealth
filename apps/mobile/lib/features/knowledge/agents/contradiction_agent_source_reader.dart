part of 'contradiction_agent.dart';

abstract class ContradictionSourceReader {
  Future<ContradictionSourceSnapshot> read(AgentContext ctx);
}

class RepositoryContradictionSourceReader implements ContradictionSourceReader {
  const RepositoryContradictionSourceReader();

  @override
  Future<ContradictionSourceSnapshot> read(AgentContext ctx) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 200,
    );
    final principles = await repo.listActivePrinciples(
      ownerUserId: ownerUserId,
    );
    final openAssumptions = await repo.listOpenAssumptions(
      ownerUserId: ownerUserId,
    );
    return ContradictionSourceSnapshot(
      decisions: decisions,
      principles: principles,
      openAssumptions: openAssumptions,
    );
  }
}

class FrbContradictionSourceReader implements ContradictionSourceReader {
  const FrbContradictionSourceReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryContradictionSourceReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final ContradictionSourceReader fallback;

  @override
  Future<ContradictionSourceSnapshot> read(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'list_triage_decisions',
          input: <String, Object?>{'limit': 200},
        ),
        AgentRuntimeEffect.tool(
          name: 'list_active_principles',
          input: <String, Object?>{'limit': 200},
        ),
        AgentRuntimeEffect.tool(
          name: 'list_open_assumptions',
          input: <String, Object?>{'limit': 200},
        ),
      ],
      maxEffectSteps: 3,
      fallback: () => fallback.read(ctx),
      decode: (terminalStep) async {
        final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
        return contradictionSourceSnapshotFromTerminalStep(
          terminalStep,
          ownerUserId: ownerUserId,
        );
      },
    );
  }
}

class ContradictionSourceSnapshot {
  const ContradictionSourceSnapshot({
    required this.decisions,
    required this.principles,
    required this.openAssumptions,
  });

  final List<KnowledgeDecision> decisions;
  final List<KnowledgePrinciple> principles;
  final List<KnowledgeAssumption> openAssumptions;
}

ContradictionSourceSnapshot? contradictionSourceSnapshotFromTerminalStep(
  Map<String, Object?> step, {
  required String ownerUserId,
}) {
  final byTool = agentRuntimeTerminalEffectResultsByToolName(step);
  final decisions = contradictionDecisionsFromToolResult(
    byTool['list_triage_decisions'],
    ownerUserId: ownerUserId,
  );
  final principles = contradictionPrinciplesFromToolResult(
    byTool['list_active_principles'],
    ownerUserId: ownerUserId,
  );
  final assumptions = contradictionAssumptionsFromToolResult(
    byTool['list_open_assumptions'],
    ownerUserId: ownerUserId,
  );
  if (decisions == null || principles == null || assumptions == null) {
    return null;
  }
  return ContradictionSourceSnapshot(
    decisions: decisions,
    principles: principles,
    openAssumptions: assumptions,
  );
}

List<KnowledgeDecision>? contradictionDecisionsFromToolResult(
  Map<String, Object?>? result, {
  required String ownerUserId,
}) {
  final rawDecisions = result?['decisions'];
  if (rawDecisions is! List) return null;
  final out = <KnowledgeDecision>[];
  for (final raw in rawDecisions) {
    final decision = _asObject(raw);
    final id = decision?['id'];
    final question = decision?['question'];
    final selected = decision?['selected'];
    final status = decision?['status'];
    final decidedAt = DateTime.tryParse(
      (decision?['decided_at'] as String?) ?? '',
    );
    if (id is! String || question is! String) return null;
    out.add(
      KnowledgeDecision(
        id: id,
        question: question,
        options: const <DecisionOption>[],
        selectedLabel: selected is String ? selected : '',
        rationaleMd: '',
        principleIds: _stringList(decision?['principle_ids']),
        assumptionIds: _stringList(decision?['assumption_ids']),
        status: status is String
            ? DecisionStatus.parse(status)
            : DecisionStatus.active,
        decidedAt:
            decidedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        sync: _syntheticSync(ownerUserId),
      ),
    );
  }
  return out;
}

List<KnowledgePrinciple>? contradictionPrinciplesFromToolResult(
  Map<String, Object?>? result, {
  required String ownerUserId,
}) {
  final rawPrinciples = result?['principles'];
  if (rawPrinciples is! List) return null;
  final out = <KnowledgePrinciple>[];
  for (final raw in rawPrinciples) {
    final principle = _asObject(raw);
    final id = principle?['id'];
    final statement = principle?['statement'];
    final declaredAt = DateTime.tryParse(
      (principle?['declared_at'] as String?) ?? '',
    );
    if (id is! String || statement is! String) return null;
    out.add(
      KnowledgePrinciple(
        id: id,
        statement: statement,
        rationaleMd: (principle?['rationale_md'] as String?) ?? '',
        scope: (principle?['scope'] as String?) ?? '*',
        status: PrincipleStatus.active,
        declaredAt:
            declaredAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        sync: _syntheticSync(ownerUserId),
      ),
    );
  }
  return out;
}

List<KnowledgeAssumption>? contradictionAssumptionsFromToolResult(
  Map<String, Object?>? result, {
  required String ownerUserId,
}) {
  final rawAssumptions = result?['assumptions'];
  if (rawAssumptions is! List) return null;
  final out = <KnowledgeAssumption>[];
  for (final raw in rawAssumptions) {
    final assumption = _asObject(raw);
    final id = assumption?['id'];
    final statement = assumption?['statement'];
    final confidence = assumption?['confidence'];
    final lastVerifiedAt = DateTime.tryParse(
      (assumption?['last_verified_at'] as String?) ?? '',
    );
    if (id is! String || statement is! String) return null;
    out.add(
      KnowledgeAssumption(
        id: id,
        statement: statement,
        confidence: confidence is num ? confidence.toDouble() : 0.7,
        scope: (assumption?['scope'] as String?) ?? '*',
        evidenceIds: const <String>[],
        status: AssumptionStatus.active,
        declaredAt:
            lastVerifiedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        lastVerifiedAt: lastVerifiedAt,
        sync: _syntheticSync(ownerUserId),
      ),
    );
  }
  return out;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

SyncMeta _syntheticSync(String ownerUserId) {
  return SyncMeta(
    ownerUserId: ownerUserId,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedByDevice: 'frb-agent-runtime',
    hlc: Hlc.zero('frb-agent-runtime'),
  );
}
