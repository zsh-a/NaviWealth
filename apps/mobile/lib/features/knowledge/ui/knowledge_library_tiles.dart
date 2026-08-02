part of 'knowledge_library_page.dart';

Widget _buildLibraryTile(
  BuildContext context, {
  required String title,
  required String query,
  required VoidCallback onPress,
  required VoidCallback onDelete,
  String? itemKey,
  IconData? typeIcon,
  Color? typeColor,
  String? statusBadge,
  List<Widget> subtitle = const <Widget>[],
}) {
  final colors = context.theme.colors;
  return AppDismissible(
    itemKey: ValueKey<String>('lib-tile-${itemKey ?? title}'),
    // The delete dialog owns the mutation; the row snaps back.
    removeRow: false,
    onTrigger: onDelete,
    borderRadius: AppRadius.sm,
    child: Semantics(
      button: true,
      label: [
        title.isEmpty ? AppLocalizations.of(context).knowledgeUntitled : title,
        ?statusBadge,
      ].join(', '),
      child: KnowledgeSection.item(
        onPress: onPress,
        children: [
          _LibraryTileHeader(
            title: title,
            query: query,
            leading: typeIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s8),
                    child: AppIconTile(
                      icon: typeIcon,
                      color: typeColor ?? colors.primary,
                      size: 28,
                      iconSize: AppIconSizes.xs,
                      radius: AppRadius.sm,
                      backgroundOpacity: AppOpacity.subtle,
                      foregroundOpacity: 1,
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statusBadge != null) ...[
                  KnowledgeStatusLabel(label: statusBadge),
                  const SizedBox(width: AppSpacing.s4),
                ],
                AppAdaptiveActionMenu(
                  title: AppLocalizations.of(
                    context,
                  ).knowledgeLibraryItemActions,
                  actions: [
                    AppAdaptiveAction(
                      icon: FLucideIcons.trash2,
                      title: AppLocalizations.of(context).commonDelete,
                      destructive: true,
                      onPress: onDelete,
                    ),
                  ],
                  triggerBuilder: (context, openMenu, focusNode) => Focus(
                    focusNode: focusNode,
                    child: AppIconButton(
                      icon: FLucideIcons.ellipsis,
                      tooltip: AppLocalizations.of(
                        context,
                      ).knowledgeLibraryItemActions,
                      onPress: openMenu,
                      size: AppControlHeights.touchTarget,
                      iconSize: AppIconSizes.xs,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...subtitle,
        ],
      ),
    ),
  );
}

Widget _buildAllTile(
  BuildContext context,
  _LibraryEntry entry, {
  required String query,
  required VoidCallback onDelete,
}) {
  final itemKey = '${entry.kind.name}:${entry.id}';
  return switch (entry.kind) {
    KnowledgeEntryKind.decision => _buildDecisionTile(
      context,
      entry.value as KnowledgeDecision,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.principle => _buildPrincipleTile(
      context,
      entry.value as KnowledgePrinciple,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.assumption => _buildAssumptionTile(
      context,
      entry.value as KnowledgeAssumption,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.note => _buildNoteTile(
      context,
      entry.value as KnowledgeNote,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.concept => _buildConceptTile(
      context,
      entry.value as KnowledgeConcept,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.experiment => _buildExperimentTile(
      context,
      entry.value as KnowledgeExperiment,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
    KnowledgeEntryKind.routine => _buildRoutineTile(
      context,
      entry.value as KnowledgeRoutine,
      query: query,
      onDelete: onDelete,
      itemKey: itemKey,
    ),
  };
}

Widget _buildDecisionTile(
  BuildContext context,
  KnowledgeDecision d, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final subtitle = <Widget>[
    if (d.selectedLabel.isNotEmpty)
      KnowledgeHighlightedText(
        text: d.selectedLabel,
        query: query,
        style: typography.body.sm.copyWith(color: colors.primary),
      ),
    if (d.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s4),
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(d.rationaleMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
    ],
  ];
  return _buildLibraryTile(
    context,
    title: d.question,
    query: query,
    itemKey: itemKey,
    statusBadge: decisionStatusLabelOf(AppLocalizations.of(context), d.status),
    typeIcon: FLucideIcons.gitBranch,
    typeColor: colors.primary,
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'decision', id: d.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildNoteTile(
  BuildContext context,
  KnowledgeNote n, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    if (n.bodyMd.isNotEmpty)
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(n.bodyMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
  ];
  return _buildLibraryTile(
    context,
    title: n.title.isEmpty ? l10n.knowledgeUntitled : n.title,
    query: query,
    itemKey: itemKey,
    typeIcon: FLucideIcons.fileText,
    typeColor: colors.mutedForeground,
    onPress: () => _openKnowledgeLibraryDetail(context, kind: 'note', id: n.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildPrincipleTile(
  BuildContext context,
  KnowledgePrinciple p, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    Text(l10n.knowledgeDetailScope(p.scope), style: context.bodyCaptionStyle),
    if (p.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s4),
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(p.rationaleMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
    ],
  ];
  return _buildLibraryTile(
    context,
    title: p.statement,
    query: query,
    itemKey: itemKey,
    statusBadge: principleStatusLabel(AppLocalizations.of(context), p.status),
    typeIcon: FLucideIcons.badgeCheck,
    typeColor: context.appTheme.categorical.adapt(
      KnowledgeTypeColors.principle,
    ),
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'principle', id: p.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildAssumptionTile(
  BuildContext context,
  KnowledgeAssumption a, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    Text(
      l10n.knowledgeDetailConfidenceScope(
        a.confidence.toStringAsFixed(2),
        a.scope,
      ),
      style: context.bodyCaptionStyle,
    ),
  ];
  return _buildLibraryTile(
    context,
    title: a.statement,
    query: query,
    itemKey: itemKey,
    statusBadge: assumptionStatusLabel(AppLocalizations.of(context), a.status),
    typeIcon: FLucideIcons.lightbulb,
    typeColor: context.appTheme.categorical.adapt(
      KnowledgeTypeColors.assumption,
    ),
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'assumption', id: a.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildConceptTile(
  BuildContext context,
  KnowledgeConcept c, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final subtitle = <Widget>[
    if (c.summaryMd.isNotEmpty)
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(c.summaryMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
  ];
  return _buildLibraryTile(
    context,
    title: c.name,
    query: query,
    itemKey: itemKey,
    typeIcon: FLucideIcons.folderTree,
    typeColor: context.appTheme.categorical.adapt(KnowledgeTypeColors.concept),
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'concept', id: c.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildExperimentTile(
  BuildContext context,
  KnowledgeExperiment e, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  return _buildLibraryTile(
    context,
    title: e.hypothesis,
    query: query,
    itemKey: itemKey,
    statusBadge: experimentStatusLabel(AppLocalizations.of(context), e.status),
    typeIcon: FLucideIcons.flaskConical,
    typeColor: context.appTheme.categorical.adapt(
      KnowledgeTypeColors.experiment,
    ),
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'experiment', id: e.id),
    onDelete: onDelete,
  );
}

Widget _buildRoutineTile(
  BuildContext context,
  KnowledgeRoutine r, {
  required String query,
  required VoidCallback onDelete,
  String? itemKey,
}) {
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final days = r.daysUntilDue(now);
  final dueLabel = days < 0
      ? l10n.knowledgeRoutineOverdueDays(-days)
      : days == 0
      ? l10n.knowledgeRoutineDueToday
      : l10n.knowledgeRoutineDueInDays(days);
  final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
  final subtitle = <Widget>[
    Text(
      l10n.knowledgeRoutineLibraryMeta(dueLabel, r.intervalDays, r.scope),
      style: context.bodyCaptionStyle.copyWith(color: dueColor),
    ),
  ];
  return _buildLibraryTile(
    context,
    title: r.statement,
    query: query,
    itemKey: itemKey,
    statusBadge: routineStatusLabel(AppLocalizations.of(context), r.status),
    typeIcon: FLucideIcons.calendarClock,
    typeColor: context.appTheme.categorical.adapt(KnowledgeTypeColors.routine),
    onPress: () =>
        _openKnowledgeLibraryDetail(context, kind: 'routine', id: r.id),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

class _LibraryTileHeader extends StatelessWidget {
  const _LibraryTileHeader({
    required this.title,
    required this.query,
    required this.trailing,
    this.leading,
  });

  final String title;
  final String query;
  final Widget trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ?leading,
          Expanded(
            child: KnowledgeHighlightedText(
              text: title,
              query: query,
              style: context.rowTitleStyle,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          trailing,
        ],
      ),
    );
  }
}
