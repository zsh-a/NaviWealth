/// KnowledgeOS Decision detail page
/// (`docs/knowledgeos-domain.md` §3 + §9 — Decision 7-state lifecycle
/// and `supersededByDecisionId` chain).
///
/// Read view + a lifecycle editor (header ✎): status changes, actual-outcome
/// capture and supersede wiring all run through [showDecisionLifecycleSheet]
/// — the write path that lets a decision read as cognitive evolution rather
/// than a frozen record.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/visual/ai_markdown.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_decision_lifecycle_sheet.dart';
import '_widgets.dart';

class KnowledgeDecisionDetailPage extends ConsumerWidget {
  const KnowledgeDecisionDetailPage({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Body(decisionId: decisionId);
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
  Object? _error;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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

      // Resolve referenced principles / assumptions by id so a decision that
      // cites a since-retired principle or falsified assumption still shows it
      // (listActive/listOpen would silently drop those — exactly the rows a
      // post-mortem cares about).
      final principles = <KnowledgePrinciple>[];
      final assumptions = <KnowledgeAssumption>[];
      for (final id in d.principleIds) {
        final p = await repo.findPrinciple(id);
        if (p != null) principles.add(p);
      }
      for (final id in d.assumptionIds) {
        final a = await repo.findAssumption(id);
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor(KnowledgeDecision d) async {
    final saved = await showDecisionLifecycleSheet(context, ref, d);
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _decision;
    return ObjectDetailScaffold(
      title: AppLocalizations.of(context).knowledgeDecisionDetailTitle,
      actions: [
        if (d != null)
          FHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            onPress: () => _openEditor(d),
          ),
      ],
      child: _buildBody(context, d),
    );
  }

  Widget _buildBody(BuildContext context, KnowledgeDecision? d) {
    if (_loading) return const KnowledgeLoadingState();
    final error = _error;
    if (error != null) {
      return KnowledgeErrorState(
        title: AppLocalizations.of(context).knowledgeLoadFailed('$error'),
        onRetry: _load,
      );
    }
    if (d == null) {
      return KnowledgeEmptyState(
        icon: FLucideIcons.fileQuestion,
        title: AppLocalizations.of(context).knowledgeDecisionNotFound,
      );
    }
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final decidedDate = knowledgeDate(context, d.decidedAt, long: true);
    final reviewDate = d.reviewDate == null
        ? null
        : knowledgeDate(context, d.reviewDate!, long: true);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        KnowledgeObjectHero(
          icon: FLucideIcons.gitBranch,
          color: colors.primary,
          typeLabel: l10n.knowledgeDecisionDetailTitle,
          title: d.question,
          status: d.status.wire,
          updatedAt: d.sync.updatedAt,
        ),
        const SizedBox(height: AppSpacing.s12),
        KnowledgeSection.group(
          title: l10n.knowledgeDetailMetadataTitle,
          children: [
            Text(
              reviewDate == null
                  ? l10n.knowledgeDecisionDecidedAt(decidedDate)
                  : l10n.knowledgeDecisionDecidedAtWithReview(
                      decidedDate,
                      reviewDate,
                    ),
              style: context.bodyCaptionStyle,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        KnowledgeSection.group(
          title: AppLocalizations.of(context).knowledgeDetailOptionsTitle,
          children: [
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
                      size: AppIconSizes.xs,
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
          ],
        ),
        if (d.rationaleMd.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: AppLocalizations.of(context).knowledgeDetailRationaleTitle,
            children: [AiMarkdown(text: d.rationaleMd)],
          ),
        ],
        if (_principles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: AppLocalizations.of(context).knowledgeDetailPrinciplesTitle,
            children: [
              for (final p in _principles)
                _RelatedKnowledgeLink(
                  label: p.statement,
                  status: p.status.wire,
                  icon: FLucideIcons.badgeCheck,
                  iconColor: KnowledgeTypeColors.principle,
                  onPress: () => context.pushNamed(
                    AppRouteNames.knowledgeObjectDetail,
                    pathParameters: {'kind': 'principle', 'id': p.id},
                  ),
                ),
            ],
          ),
        ],
        if (_assumptions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: AppLocalizations.of(context).knowledgeDetailAssumptionsTitle,
            children: [
              for (final a in _assumptions)
                _RelatedKnowledgeLink(
                  label: a.statement,
                  status:
                      '${a.status.wire} · ${a.confidence.toStringAsFixed(2)}',
                  icon: FLucideIcons.lightbulb,
                  iconColor: KnowledgeTypeColors.assumption,
                  onPress: () => context.pushNamed(
                    AppRouteNames.knowledgeObjectDetail,
                    pathParameters: {'kind': 'assumption', 'id': a.id},
                  ),
                ),
            ],
          ),
        ],
        if (d.expectedOutcome != null && d.expectedOutcome!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: AppLocalizations.of(
              context,
            ).knowledgeDetailExpectedOutcomeTitle,
            children: [Text(d.expectedOutcome!, style: typography.sm)],
          ),
        ],
        if (d.actualOutcomeMd != null && d.actualOutcomeMd!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeSection.group(
            title: AppLocalizations.of(
              context,
            ).knowledgeDetailActualOutcomeTitle,
            children: [AiMarkdown(text: d.actualOutcomeMd!)],
          ),
        ],
        if (d.contextSnapshot != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _ContextSnapshotSection(
            snapshot: d.contextSnapshot!,
            collapsible: true,
          ),
        ],
        if (_chain.length > 1) ...[
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: AppLocalizations.of(context).knowledgeDetailEvolutionTitle,
            collapsible: true,
            initiallyExpanded: false,
            children: [
              for (var i = 0; i < _chain.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                  child: Row(
                    children: [
                      Icon(
                        i == 0
                            ? FLucideIcons.arrowRightCircle
                            : FLucideIcons.arrowUpCircle,
                        size: AppIconSizes.xs,
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
            ],
          ),
        ],
      ],
    );
  }
}

class _RelatedKnowledgeLink extends StatelessWidget {
  const _RelatedKnowledgeLink({
    required this.label,
    required this.status,
    required this.onPress,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String status;
  final VoidCallback onPress;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: AppSpacing.s8, top: 2),
                decoration: BoxDecoration(
                  color: (iconColor ?? colors.primary).withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(icon, size: 13, color: iconColor ?? colors.primary),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: typography.sm,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    status,
                    style: typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.xs,
              color: colors.mutedForeground.withValues(alpha: AppOpacity.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders `KnowledgeDecision.contextSnapshot` — what was happening
/// across other domains when the decision was made. The snapshot
/// shape is owned by `DecisionContextSnapper`; this widget is the
/// only reader and tolerates missing keys silently.
class _ContextSnapshotSection extends StatelessWidget {
  const _ContextSnapshotSection({
    required this.snapshot,
    this.collapsible = false,
  });
  final Map<String, Object?> snapshot;
  final bool collapsible;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final finance = (snapshot['recent_finance_events'] as List?) ?? const [];
    final health = (snapshot['recent_health_events'] as List?) ?? const [];
    final capturedAt = snapshot['captured_at'] as String?;
    final window = snapshot['window_days'];
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[
      if (capturedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
          child: Text(
            l10n.knowledgeDetailContextSnapshotCaptured(
              knowledgeDateFromIso(context, capturedAt),
              '${window ?? "—"}',
            ),
            style: context.captionStyle,
          ),
        ),
      if (finance.isEmpty && health.isEmpty)
        Text(
          l10n.knowledgeDetailContextSnapshotEmpty,
          style: context.bodyCaptionStyle,
        ),
      if (finance.isNotEmpty) ...[
        Text(l10n.knowledgeDetailContextSnapshotFinance, style: typography.xs),
        for (final raw in finance.whereType<Map<Object?, Object?>>())
          _SnapshotRow(map: raw.cast<String, Object?>()),
        const SizedBox(height: AppSpacing.s4),
      ],
      if (health.isNotEmpty) ...[
        Text(l10n.knowledgeDetailContextSnapshotHealth, style: typography.xs),
        for (final raw in health.whereType<Map<Object?, Object?>>())
          _SnapshotRow(map: raw.cast<String, Object?>()),
      ],
    ];
    if (collapsible) {
      return KnowledgeWriterSection(
        title: l10n.knowledgeDetailContextSnapshotTitle,
        collapsible: true,
        initiallyExpanded: false,
        children: children,
      );
    }
    return KnowledgeSection.group(
      title: l10n.knowledgeDetailContextSnapshotTitle,
      children: children,
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.map});
  final Map<String, Object?> map;
  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final ts = (map['timestamp'] as String?) ?? '';
    final summary = (map['summary'] as String?) ?? '';
    final title = (map['title'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.s8,
                top: AppSpacing.s2,
              ),
              child: Text(
                knowledgeMonthDayFromIso(context, ts),
                style: context.captionStyle,
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
