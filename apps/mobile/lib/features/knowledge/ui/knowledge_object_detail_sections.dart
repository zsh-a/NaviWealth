part of 'knowledge_object_detail_page.dart';

// ── Per-type section builders ──────────────────────────────────────────────

class _ObjectHeader extends StatelessWidget {
  const _ObjectHeader({
    required this.kind,
    required this.title,
    required this.updatedAt,
    this.status,
  });

  final KnowledgeObjectKind kind;
  final String title;
  final DateTime updatedAt;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KnowledgeObjectHeader(
      icon: _kindIcon(kind),
      color: _kindColor(context, kind),
      typeLabel: _kindLabel(l10n, kind),
      title: title,
      updatedAt: updatedAt,
      status: status,
    );
  }
}

IconData _kindIcon(KnowledgeObjectKind kind) => switch (kind) {
  KnowledgeObjectKind.note => FLucideIcons.fileText,
  KnowledgeObjectKind.concept => FLucideIcons.folderTree,
  KnowledgeObjectKind.experiment => FLucideIcons.flaskConical,
  KnowledgeObjectKind.principle => FLucideIcons.badgeCheck,
  KnowledgeObjectKind.assumption => FLucideIcons.lightbulb,
  KnowledgeObjectKind.routine => FLucideIcons.calendarClock,
};

Color _kindColor(BuildContext context, KnowledgeObjectKind kind) =>
    switch (kind) {
      KnowledgeObjectKind.note => context.theme.colors.mutedForeground,
      KnowledgeObjectKind.concept => context.appTheme.categorical.adapt(
        KnowledgeTypeColors.concept,
      ),
      KnowledgeObjectKind.experiment => context.appTheme.categorical.adapt(
        KnowledgeTypeColors.experiment,
      ),
      KnowledgeObjectKind.principle => context.appTheme.categorical.adapt(
        KnowledgeTypeColors.principle,
      ),
      KnowledgeObjectKind.assumption => context.appTheme.categorical.adapt(
        KnowledgeTypeColors.assumption,
      ),
      KnowledgeObjectKind.routine => context.appTheme.categorical.adapt(
        KnowledgeTypeColors.routine,
      ),
    };

String _kindLabel(AppLocalizations l10n, KnowledgeObjectKind kind) {
  return switch (kind) {
    KnowledgeObjectKind.note => l10n.knowledgeNoteDetailTitle,
    KnowledgeObjectKind.concept => l10n.knowledgeConceptDetailTitle,
    KnowledgeObjectKind.experiment => l10n.knowledgeExperimentDetailTitle,
    KnowledgeObjectKind.principle => l10n.knowledgePrincipleDetailTitle,
    KnowledgeObjectKind.assumption => l10n.knowledgeAssumptionDetailTitle,
    KnowledgeObjectKind.routine => l10n.knowledgeRoutineDetailTitle,
  };
}

List<Widget> _noteSections(BuildContext context, KnowledgeNote n) {
  final l10n = AppLocalizations.of(context);
  final title = n.title.trim().isEmpty ? l10n.knowledgeUntitled : n.title;
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.note,
      title: title,
      updatedAt: n.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: l10n.knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, n.createdAt, long: true),
        ),
        _MetaPill(
          label: l10n.knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, n.sync.updatedAt, long: true),
        ),
        if (n.projectTag != null && n.projectTag!.isNotEmpty)
          _MetaPill(
            label: l10n.knowledgeDetailProjectLabel,
            value: n.projectTag!,
          ),
        if (n.tags.isNotEmpty)
          _MetaPill(
            label: l10n.knowledgeDetailTagsLabel,
            value: n.tags.join(' · '),
          ),
      ],
    ),
    if (n.bodyMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: l10n.knowledgeDetailBodyTitle,
        child: KnowledgeMarkdown(text: n.bodyMd),
      ),
    ],
    if (n.sourceUrl != null && n.sourceUrl!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: l10n.knowledgeDetailSourceTitle,
        children: [Text(n.sourceUrl!, style: context.bodyCaptionStyle)],
      ),
    ],
  ];
}

List<Widget> _conceptSections(
  BuildContext context,
  KnowledgeConcept c, {
  required List<KnowledgeConcept> relatedConcepts,
}) {
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.concept,
      title: c.name,
      updatedAt: c.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, c.createdAt, long: true),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, c.sync.updatedAt, long: true),
        ),
        if (c.aliases.isNotEmpty)
          _MetaPill(
            label: AppLocalizations.of(context).knowledgeDetailAliasesLabel,
            value: c.aliases.join(' · '),
          ),
      ],
    ),
    if (c.summaryMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: AppLocalizations.of(context).knowledgeDetailSummaryTitle,
        child: KnowledgeMarkdown(text: c.summaryMd),
      ),
    ],
    if (relatedConcepts.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailRelatedConceptsTitle,
        children: [
          for (final concept in relatedConcepts)
            _RelatedObjectLink(
              label: concept.name,
              meta: concept.aliases.isEmpty
                  ? AppLocalizations.of(context).knowledgeConceptDetailTitle
                  : concept.aliases.join(' · '),
              icon: FLucideIcons.folderTree,
              iconColor: context.appTheme.categorical.adapt(
                KnowledgeTypeColors.concept,
              ),
              onPress: () => context.pushNamed(
                KnowledgeRouteNames.objectDetail,
                pathParameters: {'kind': 'concept', 'id': concept.id},
              ),
            ),
        ],
      ),
    ],
  ];
}

List<Widget> _experimentSections(
  BuildContext context,
  KnowledgeExperiment e, {
  required KnowledgeAssumption? targetAssumption,
}) {
  final typography = context.theme.typography;
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.experiment,
      title: e.hypothesis,
      status: experimentStatusLabel(AppLocalizations.of(context), e.status),
      updatedAt: e.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailStartedLabel,
          value: knowledgeDate(context, e.startedAt, long: true),
        ),
        if (e.endedAt != null)
          _MetaPill(
            label: AppLocalizations.of(context).knowledgeDetailEndedLabel,
            value: knowledgeDate(context, e.endedAt!, long: true),
          ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, e.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (targetAssumption != null) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(
          context,
        ).knowledgeDetailTargetAssumptionTitle,
        children: [
          _RelatedObjectLink(
            label: targetAssumption.statement,
            meta:
                '${assumptionStatusLabel(AppLocalizations.of(context), targetAssumption.status)}'
                ' · ${targetAssumption.confidence.toStringAsFixed(2)}',
            icon: FLucideIcons.lightbulb,
            iconColor: context.appTheme.categorical.adapt(
              KnowledgeTypeColors.assumption,
            ),
            onPress: () => context.pushNamed(
              KnowledgeRouteNames.objectDetail,
              pathParameters: {'kind': 'assumption', 'id': targetAssumption.id},
            ),
          ),
        ],
      ),
    ],
    if (e.methodMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: AppLocalizations.of(context).knowledgeDetailMethodTitle,
        child: KnowledgeMarkdown(text: e.methodMd),
      ),
    ],
    if (e.metrics.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailMetricsTitle,
        children: [Text(e.metrics.join(' · '), style: typography.body.sm)],
      ),
    ],
    if (e.resultMd != null && e.resultMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: AppLocalizations.of(context).knowledgeDetailResultTitle,
        child: KnowledgeMarkdown(text: e.resultMd!),
      ),
    ],
    if (e.conclusionMd != null && e.conclusionMd!.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: AppLocalizations.of(context).knowledgeDetailConclusionTitle,
        child: KnowledgeMarkdown(text: e.conclusionMd!),
      ),
    ],
  ];
}

List<Widget> _principleSections(
  BuildContext context,
  KnowledgePrinciple p, {
  required List<KnowledgeDecision> referencingDecisions,
}) {
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.principle,
      title: p.statement,
      status: principleStatusLabel(AppLocalizations.of(context), p.status),
      updatedAt: p.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailScopeLabel,
          value: p.scope,
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailDeclaredLabel,
          value: knowledgeDate(context, p.declaredAt, long: true),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, p.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (p.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeDocumentSection(
        title: AppLocalizations.of(context).knowledgeDetailRationaleTitle,
        child: KnowledgeMarkdown(text: p.rationaleMd),
      ),
    ],
    if (referencingDecisions.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      _DecisionLinksSection(decisions: referencingDecisions),
    ],
  ];
}

List<Widget> _assumptionSections(
  BuildContext context,
  KnowledgeAssumption a, {
  required List<KnowledgeNote> evidenceNotes,
  required List<KnowledgeDecision> referencingDecisions,
  required List<KnowledgeExperiment> targetingExperiments,
}) {
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.assumption,
      title: a.statement,
      status: assumptionStatusLabel(AppLocalizations.of(context), a.status),
      updatedAt: a.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailConfidenceLabel,
          value: a.confidence.toStringAsFixed(2),
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailScopeLabel,
          value: a.scope,
        ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailDeclaredLabel,
          value: knowledgeDate(context, a.declaredAt, long: true),
        ),
        if (a.lastVerifiedAt != null)
          _MetaPill(
            label: AppLocalizations.of(
              context,
            ).knowledgeDetailLastVerifiedLabel,
            value: knowledgeDate(context, a.lastVerifiedAt!, long: true),
          ),
        _MetaPill(
          label: AppLocalizations.of(context).knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, a.sync.updatedAt, long: true),
        ),
      ],
    ),
    if (evidenceNotes.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailEvidenceTitle,
        children: [
          for (final note in evidenceNotes)
            _RelatedObjectLink(
              label: note.title.isEmpty
                  ? AppLocalizations.of(context).knowledgeUntitled
                  : note.title,
              meta: note.bodyMd.trim().isEmpty
                  ? knowledgeDate(context, note.createdAt, long: true)
                  : knowledgeExcerpt(note.bodyMd),
              icon: FLucideIcons.fileText,
              iconColor: context.theme.colors.mutedForeground,
              onPress: () => context.pushNamed(
                KnowledgeRouteNames.objectDetail,
                pathParameters: {'kind': 'note', 'id': note.id},
              ),
            ),
        ],
      ),
    ],
    if (referencingDecisions.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      _DecisionLinksSection(decisions: referencingDecisions),
    ],
    if (targetingExperiments.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s12),
      KnowledgeSection.group(
        title: AppLocalizations.of(context).knowledgeDetailExperimentsTitle,
        children: [
          for (final experiment in targetingExperiments)
            _RelatedObjectLink(
              label: experiment.hypothesis,
              meta: experimentStatusLabel(
                AppLocalizations.of(context),
                experiment.status,
              ),
              icon: FLucideIcons.flaskConical,
              iconColor: context.appTheme.categorical.adapt(
                KnowledgeTypeColors.experiment,
              ),
              onPress: () => context.pushNamed(
                KnowledgeRouteNames.objectDetail,
                pathParameters: {'kind': 'experiment', 'id': experiment.id},
              ),
            ),
        ],
      ),
    ],
  ];
}

List<Widget> _routineSections(BuildContext context, KnowledgeRoutine r) {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final days = r.daysUntilDue(now);
  final dueLabel = days < 0
      ? l10n.knowledgeRoutineOverdueDays(-days)
      : days == 0
      ? l10n.knowledgeRoutineDueToday
      : l10n.knowledgeRoutineDueInDays(days);
  return [
    _ObjectHeader(
      kind: KnowledgeObjectKind.routine,
      title: r.statement,
      status: routineStatusLabel(AppLocalizations.of(context), r.status),
      updatedAt: r.sync.updatedAt,
    ),
    const SizedBox(height: AppSpacing.s12),
    _MetadataSection(
      children: [
        _MetaPill(
          label: l10n.knowledgeDetailNextDueLabel,
          value:
              '${knowledgeDate(context, r.nextDueAt, long: true)} · $dueLabel',
        ),
        if (r.lastDoneAt != null)
          _MetaPill(
            label: l10n.knowledgeDetailLastDoneLabel,
            value: knowledgeDate(context, r.lastDoneAt!, long: true),
          ),
        _MetaPill(
          label: l10n.knowledgeDetailIntervalLabel,
          value: l10n.knowledgeProposalIntervalDays(r.intervalDays),
        ),
        _MetaPill(label: l10n.knowledgeDetailScopeLabel, value: r.scope),
        _MetaPill(
          label: l10n.knowledgeDetailCreatedLabel,
          value: knowledgeDate(context, r.createdAt, long: true),
        ),
        _MetaPill(
          label: l10n.knowledgeDetailUpdatedLabel,
          value: knowledgeDate(context, r.sync.updatedAt, long: true),
        ),
      ],
    ),
  ];
}
