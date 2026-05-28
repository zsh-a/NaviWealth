/// KnowledgeOS Decision detail page
/// (`docs/knowledgeos-domain.md` §3 + §9 — Decision 7-state lifecycle
/// and `supersededByDecisionId` chain).
///
/// Read-only MVP. Status edits / actual-outcome capture / supersede
/// wiring are the natural follow-ups but live as §14.2 P2 (dogfood
/// will tell us which gets used first).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

class KnowledgeDecisionDetailPage extends ConsumerWidget {
  const KnowledgeDecisionDetailPage({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      header: const FHeader.nested(title: Text('Decision')),
      childPad: false,
      child: _Body(decisionId: decisionId),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.decisionId});
  final String decisionId;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  KnowledgeDecision? _decision;
  List<KnowledgeDecision> _chain = const <KnowledgeDecision>[];
  List<KnowledgePrinciple> _principles = const <KnowledgePrinciple>[];
  List<KnowledgeAssumption> _assumptions = const <KnowledgeAssumption>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final d = await repo.findDecision(widget.decisionId);
    if (d == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Walk supersededBy chain backwards (current → ancestor) until null.
    final chain = <KnowledgeDecision>[d];
    var cursor = d;
    final visited = <String>{d.id};
    while (cursor.supersededByDecisionId != null &&
        !visited.contains(cursor.supersededByDecisionId)) {
      final next = await repo.findDecision(cursor.supersededByDecisionId!);
      if (next == null) break;
      visited.add(next.id);
      chain.add(next);
      cursor = next;
    }

    // Resolve referenced principles / assumptions.
    final principles = <KnowledgePrinciple>[];
    final assumptions = <KnowledgeAssumption>[];
    final allPrinciples = await repo.listActivePrinciples(
      ownerUserId: d.sync.ownerUserId,
    );
    final allAssumptions = await repo.listOpenAssumptions(
      ownerUserId: d.sync.ownerUserId,
    );
    final pById = <String, KnowledgePrinciple>{
      for (final p in allPrinciples) p.id: p,
    };
    final aById = <String, KnowledgeAssumption>{
      for (final a in allAssumptions) a.id: a,
    };
    for (final id in d.principleIds) {
      final p = pById[id];
      if (p != null) principles.add(p);
    }
    for (final id in d.assumptionIds) {
      final a = aById[id];
      if (a != null) assumptions.add(a);
    }

    if (mounted) {
      setState(() {
        _decision = d;
        _chain = chain;
        _principles = principles;
        _assumptions = assumptions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FProgress());
    final d = _decision;
    if (d == null) {
      return const Center(child: Text('Decision 不存在或已删除'));
    }
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                d.question,
                style: typography.lg
                    .copyWith(fontWeight: FontWeight.w600),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            KnowledgeStatusBadge(label: d.status.wire),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          '决策于 ${d.decidedAt.toLocal().toIso8601String().substring(0, 10)}'
          '${d.reviewDate != null ? '  ·  复盘 ${d.reviewDate!.toLocal().toIso8601String().substring(0, 10)}' : ''}',
          style: typography.xs.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: AppSpacing.s16),
        KnowledgeSection.group(title: '选项', children: [
          for (final opt in d.options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    opt.label == d.selectedLabel
                        ? FLucideIcons.checkCircle2
                        : FLucideIcons.circle,
                    size: 14,
                    color: opt.label == d.selectedLabel
                        ? colors.primary
                        : colors.mutedForeground,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt.label,
                          style: typography.sm.copyWith(
                            fontWeight: opt.label == d.selectedLabel
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (opt.rationale != null &&
                            opt.rationale!.isNotEmpty)
                          Text(
                            opt.rationale!,
                            style: typography.xs.copyWith(
                              color: colors.mutedForeground,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ]),
        if (d.rationaleMd.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: '理由',
            children: [AiMarkdown(text: d.rationaleMd)],
          ),
        ],
        if (_principles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(title: '引用的 Principle', children: [
            for (final p in _principles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '· ${p.statement}',
                  style: typography.sm,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
        ],
        if (_assumptions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(title: '引用的 Assumption', children: [
            for (final a in _assumptions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '· ${a.statement}（conf ${a.confidence.toStringAsFixed(2)}）',
                  style: typography.sm,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
        ],
        if (d.expectedOutcome != null && d.expectedOutcome!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: '预期结果',
            children: [Text(d.expectedOutcome!, style: typography.sm)],
          ),
        ],
        if (d.actualOutcomeMd != null && d.actualOutcomeMd!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: '实际结果',
            children: [AiMarkdown(text: d.actualOutcomeMd!)],
          ),
        ],
        if (d.contextSnapshot != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _ContextSnapshotSection(snapshot: d.contextSnapshot!),
        ],
        if (_chain.length > 1) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(title: '认知演化链', children: [
            for (var i = 0; i < _chain.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      i == 0
                          ? FLucideIcons.arrowRightCircle
                          : FLucideIcons.arrowUpCircle,
                      size: 14,
                      color: colors.mutedForeground,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        '${_chain[i].question}（${_chain[i].status.wire}）',
                        style: typography.sm,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        ],
      ],
    );
  }
}

/// Renders `KnowledgeDecision.contextSnapshot` — what was happening
/// across other domains when the decision was made. The snapshot
/// shape is owned by `DecisionContextSnapper`; this widget is the
/// only reader and tolerates missing keys silently.
class _ContextSnapshotSection extends StatelessWidget {
  const _ContextSnapshotSection({required this.snapshot});
  final Map<String, Object?> snapshot;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final finance = (snapshot['recent_finance_events'] as List?) ?? const [];
    final health = (snapshot['recent_health_events'] as List?) ?? const [];
    final capturedAt = snapshot['captured_at'] as String?;
    final window = snapshot['window_days'];
    return KnowledgeSection.group(title: '当时的跨域状态', children: [
      if (capturedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
          child: Text(
            '采样于 ${capturedAt.substring(0, 10)} · 窗口 ${window ?? "—"} 天',
            style:
                typography.xs.copyWith(color: colors.mutedForeground),
          ),
        ),
      if (finance.isEmpty && health.isEmpty)
        Text(
          '当时窗口内无 Finance / Health 事件。',
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
      if (finance.isNotEmpty) ...[
        Text(
          'Finance',
          style: typography.xs.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final raw in finance.whereType<Map<Object?, Object?>>())
          _SnapshotRow(map: raw.cast<String, Object?>()),
        const SizedBox(height: AppSpacing.s4),
      ],
      if (health.isNotEmpty) ...[
        Text(
          'Health',
          style: typography.xs.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final raw in health.whereType<Map<Object?, Object?>>())
          _SnapshotRow(map: raw.cast<String, Object?>()),
      ],
    ]);
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.map});
  final Map<String, Object?> map;
  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final ts = (map['timestamp'] as String?) ?? '';
    final summary = (map['summary'] as String?) ?? '';
    final title = (map['title'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ts.length >= 10)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s8, top: 2),
              child: Text(
                ts.substring(5, 10),
                style: typography.xs
                    .copyWith(color: colors.mutedForeground),
              ),
            ),
          Expanded(
            child: Text(
              title.isEmpty ? summary : '$title — $summary',
              style: typography.sm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

