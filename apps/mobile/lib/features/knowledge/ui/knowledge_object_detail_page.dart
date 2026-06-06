/// KnowledgeOS read-only detail page for the non-Decision typed objects
/// (`docs/knowledgeos-domain.md` §3 — Concept / Experiment / Principle /
/// Assumption).
///
/// Decision has its own editable page; these four share one read view
/// keyed by `:kind` so every Library tile is tappable (the interaction
/// asymmetry called out in the 2026-05-29 audit). Loading is by id via
/// the repository `findX` accessors, so a referenced-but-archived row
/// still resolves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// The kinds this page can render. Mirrors the `:kind` path segment.
enum KnowledgeObjectKind {
  concept,
  experiment,
  principle,
  assumption;

  static KnowledgeObjectKind? parse(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

class KnowledgeObjectDetailPage extends ConsumerStatefulWidget {
  const KnowledgeObjectDetailPage({
    super.key,
    required this.kind,
    required this.id,
  });
  final String kind;
  final String id;

  @override
  ConsumerState<KnowledgeObjectDetailPage> createState() =>
      _KnowledgeObjectDetailPageState();
}

class _KnowledgeObjectDetailPageState
    extends ConsumerState<KnowledgeObjectDetailPage> {
  Object? _object;
  Object? _error;
  bool _loading = true;

  KnowledgeObjectKind? get _kind => KnowledgeObjectKind.parse(widget.kind);

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
    final kind = _kind;
    if (kind == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final obj = await _fetch(repo, kind, widget.id);
      if (mounted) {
        setState(() {
          _object = obj;
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

  Future<Object?> _fetch(
    KnowledgeRepository repo,
    KnowledgeObjectKind kind,
    String id,
  ) {
    return switch (kind) {
      KnowledgeObjectKind.concept => repo.findConcept(id),
      KnowledgeObjectKind.experiment => repo.findExperiment(id),
      KnowledgeObjectKind.principle => repo.findPrinciple(id),
      KnowledgeObjectKind.assumption => repo.findAssumption(id),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ObjectDetailScaffold(title: _title(context), child: _buildBody());
  }

  String _title(BuildContext context) => switch (_kind) {
    KnowledgeObjectKind.concept => AppLocalizations.of(
      context,
    ).knowledgeConceptDetailTitle,
    KnowledgeObjectKind.experiment => AppLocalizations.of(
      context,
    ).knowledgeExperimentDetailTitle,
    KnowledgeObjectKind.principle => AppLocalizations.of(
      context,
    ).knowledgePrincipleDetailTitle,
    KnowledgeObjectKind.assumption => AppLocalizations.of(
      context,
    ).knowledgeAssumptionDetailTitle,
    null => AppLocalizations.of(context).knowledgeObjectDetailTitle,
  };

  Widget _buildBody() {
    if (_loading) return const KnowledgeLoadingState();
    final error = _error;
    if (error != null) {
      return KnowledgeErrorState(
        title: AppLocalizations.of(context).knowledgeLoadFailed('$error'),
        onRetry: _load,
      );
    }
    final obj = _object;
    if (obj == null) {
      return KnowledgeEmptyState(
        icon: FLucideIcons.fileQuestion,
        title: AppLocalizations.of(context).knowledgeObjectNotFound,
      );
    }
    final children = switch (obj) {
      final KnowledgeConcept c => _conceptSections(context, c),
      final KnowledgeExperiment e => _experimentSections(context, e),
      final KnowledgePrinciple p => _principleSections(context, p),
      final KnowledgeAssumption a => _assumptionSections(context, a),
      _ => const <Widget>[],
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: children,
    );
  }
}

// ── Per-type section builders ──────────────────────────────────────────────

Widget _heading(BuildContext context, String text, {String? badge}) {
  final typography = context.theme.typography;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(text, style: typography.lg)),
      if (badge != null) ...[
        const SizedBox(width: AppSpacing.s8),
        KnowledgeStatusLabel(label: badge),
      ],
    ],
  );
}

List<Widget> _conceptSections(BuildContext context, KnowledgeConcept c) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return [
    _heading(context, c.name),
    if (c.aliases.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s4),
      Text(
        AppLocalizations.of(
          context,
        ).knowledgeDetailAliases(c.aliases.join(' · ')),
        style: typography.xs.copyWith(color: colors.mutedForeground),
      ),
    ],
    if (c.summaryMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s16),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailSummaryTitle,
        children: [AiMarkdown(text: c.summaryMd)],
      ),
    ],
    if (c.relatedConceptIds.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailRelatedConceptsTitle,
        children: [
          Text(
            AppLocalizations.of(
              context,
            ).knowledgeDetailRelatedConceptCount(c.relatedConceptIds.length),
            style: typography.sm,
          ),
        ],
      ),
    ],
  ];
}

List<Widget> _experimentSections(BuildContext context, KnowledgeExperiment e) {
  final typography = context.theme.typography;
  return [
    _heading(context, e.hypothesis, badge: e.status.wire),
    if (e.methodMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s16),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailMethodTitle,
        children: [AiMarkdown(text: e.methodMd)],
      ),
    ],
    if (e.metrics.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailMetricsTitle,
        children: [Text(e.metrics.join(' · '), style: typography.sm)],
      ),
    ],
    if (e.resultMd != null && e.resultMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailResultTitle,
        children: [AiMarkdown(text: e.resultMd!)],
      ),
    ],
    if (e.conclusionMd != null && e.conclusionMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailConclusionTitle,
        children: [AiMarkdown(text: e.conclusionMd!)],
      ),
    ],
  ];
}

List<Widget> _principleSections(BuildContext context, KnowledgePrinciple p) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return [
    _heading(context, p.statement, badge: p.status.wire),
    const SizedBox(height: AppSpacing.s4),
    Text(
      AppLocalizations.of(context).knowledgeDetailScope(p.scope),
      style: typography.xs.copyWith(color: colors.mutedForeground),
    ),
    if (p.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s16),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailRationaleTitle,
        children: [AiMarkdown(text: p.rationaleMd)],
      ),
    ],
  ];
}

List<Widget> _assumptionSections(BuildContext context, KnowledgeAssumption a) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return [
    _heading(context, a.statement, badge: a.status.wire),
    const SizedBox(height: AppSpacing.s4),
    Text(
      AppLocalizations.of(context).knowledgeDetailConfidenceScope(
        a.confidence.toStringAsFixed(2),
        a.scope,
      ),
      style: typography.xs.copyWith(color: colors.mutedForeground),
    ),
    if (a.evidenceIds.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s16),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailEvidenceTitle,
        children: [
          Text(
            AppLocalizations.of(
              context,
            ).knowledgeDetailEvidenceCount(a.evidenceIds.length),
            style: typography.sm,
          ),
        ],
      ),
    ],
  ];
}
