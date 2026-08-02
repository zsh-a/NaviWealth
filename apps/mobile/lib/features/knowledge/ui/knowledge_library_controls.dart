part of 'knowledge_library_page.dart';

class _SearchAssistRow extends StatelessWidget {
  const _SearchAssistRow({
    required this.history,
    required this.suggestions,
    required this.query,
    required this.onSelected,
    required this.onHistoryClear,
    this.onHistoryItemDelete,
  });

  final List<String> history;
  final List<String> suggestions;
  final String query;
  final ValueChanged<String> onSelected;
  final VoidCallback onHistoryClear;
  final ValueChanged<String>? onHistoryItemDelete;

  bool get hasContent =>
      suggestions.isNotEmpty ||
      (query.isEmpty
          ? history.isNotEmpty
          : history.any((item) => item.toLowerCase().contains(query)));

  @override
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final visibleHistory = query.isEmpty
        ? history
        : history
              .where((item) => item.toLowerCase().contains(query))
              .toList(growable: false);
    final chips = <Widget>[
      if (visibleHistory.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchRecent,
          values: visibleHistory,
          icon: FLucideIcons.history,
          onSelected: onSelected,
          onClear: query.isEmpty ? onHistoryClear : null,
          onItemDelete: onHistoryItemDelete,
        ),
      if (suggestions.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchSuggestions,
          values: suggestions,
          icon: FLucideIcons.sparkles,
          onSelected: onSelected,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s8),
          chips[i],
        ],
      ],
    );
  }
}

class _SearchAssistGroup extends StatelessWidget {
  const _SearchAssistGroup({
    required this.label,
    required this.values,
    required this.icon,
    required this.onSelected,
    this.onClear,
    this.onItemDelete,
  });

  final String label;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final VoidCallback? onClear;
  final ValueChanged<String>? onItemDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final visibleValues = values.take(6).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s4),
            Text(label, style: context.captionStyle),
            if (onClear != null) ...[
              const SizedBox(width: AppSpacing.s4),
              FButton.icon(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                onPress: onClear,
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < visibleValues.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.s6),
                  _SearchAssistChip(
                    value: visibleValues[i],
                    onPress: () => onSelected(visibleValues[i]),
                    onDelete: onItemDelete != null
                        ? () => onItemDelete!(visibleValues[i])
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchAssistChip extends StatelessWidget {
  const _SearchAssistChip({
    required this.value,
    required this.onPress,
    this.onDelete,
  });

  final String value;
  final VoidCallback onPress;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.flat(
      onPress: onPress,
      padding: EdgeInsets.only(
        left: AppSpacing.s8,
        right: onDelete != null ? AppSpacing.s4 : AppSpacing.s8,
        top: AppSpacing.s4,
        bottom: AppSpacing.s4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: Text(
              value,
              style: context.captionLabelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: AppSpacing.s2),
            AppIconButton(
              icon: FLucideIcons.x,
              tooltip: AppLocalizations.of(
                context,
              ).knowledgeLibraryDeleteTooltip,
              onPress: onDelete,
              size: AppControlHeights.touchTarget,
              iconSize: AppIconSizes.xs,
              iconColor: colors.mutedForeground,
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryFilterTrigger extends StatelessWidget {
  const _LibraryFilterTrigger({
    required this.activeCount,
    required this.onPress,
  });

  final int activeCount;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = activeCount == 0
        ? l10n.knowledgeLibraryFilterTitle
        : '${l10n.knowledgeLibraryFilterTitle} · $activeCount';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppQuietButton(
        label: label,
        onPress: onPress,
        prefix: const Icon(FLucideIcons.listFilter, size: AppIconSizes.xs),
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.icon,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: l10n.knowledgeLibraryFilterAll,
                  active: selected == null,
                  onTap: () => onChanged(null),
                ),
                for (final value in values)
                  _FilterPill(
                    label: value,
                    active: selected == value,
                    onTap: () => onChanged(value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s4),
      child: AppFilterChip(label: label, active: active, onPress: onTap),
    );
  }
}

class _DateFilterChipRow extends StatelessWidget {
  const _DateFilterChipRow({required this.selected, required this.onChanged});

  final KnowledgeLibraryDateFilter selected;
  final ValueChanged<KnowledgeLibraryDateFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          FLucideIcons.calendarDays,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in KnowledgeLibraryDateFilter.values)
                  _FilterPill(
                    label: _dateFilterLabel(l10n, filter),
                    active: selected == filter,
                    onTap: () => onChanged(filter),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single compact type picker keeps the eight-object taxonomy out of the
/// primary reading flow on every screen size.
class _LibraryTabBar extends ConsumerWidget {
  const _LibraryTabBar({required this.selected, required this.onChanged});

  final _LibrarySegment selected;
  final ValueChanged<_LibrarySegment> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final owner = ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId;
    final counts =
        ref.watch(_knowledgeLibrarySegmentCountsProvider(owner)).value ??
        const <_LibrarySegment, int>{};
    final count = counts[selected];
    final scope = count == null
        ? _segmentLabel(l10n, selected)
        : l10n.knowledgeLibraryTypeScope(_segmentLabel(l10n, selected), count);
    return _LibraryTypeTrigger(
      label: scope,
      onPress: () async {
        final next = await _showLibraryTypePicker(
          context: context,
          selected: selected,
          counts: counts,
        );
        if (next != null) _select(next);
      },
    );
  }

  void _select(_LibrarySegment segment) {
    if (segment == selected) return;
    AppInteraction.signal(AppInteractionIntent.select);
    onChanged(segment);
  }
}

class _LibraryTypeTrigger extends StatelessWidget {
  const _LibraryTypeTrigger({required this.label, required this.onPress});

  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: label,
      child: AppTappable(
        key: const ValueKey<String>('knowledge-library.type-picker'),
        onPress: onPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: AppOpacity.disabled),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: colors.border.withValues(alpha: AppOpacity.highlight),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppControlHeights.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: Row(
                children: [
                  Icon(
                    FLucideIcons.library,
                    size: AppIconSizes.sm,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.labelStyle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Icon(
                    FLucideIcons.chevronsUpDown,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_LibrarySegment?> _showLibraryTypePicker({
  required BuildContext context,
  required _LibrarySegment selected,
  required Map<_LibrarySegment, int> counts,
}) {
  final l10n = AppLocalizations.of(context);
  final groups = <(String?, List<_LibrarySegment>)>[
    (null, const <_LibrarySegment>[_LibrarySegment.all]),
    (
      l10n.knowledgeLibraryTypeGroupCore,
      const <_LibrarySegment>[_LibrarySegment.decisions],
    ),
    (
      l10n.knowledgeLibraryTypeGroupSources,
      const <_LibrarySegment>[_LibrarySegment.notes, _LibrarySegment.concepts],
    ),
    (
      l10n.knowledgeLibraryTypeGroupThinking,
      const <_LibrarySegment>[
        _LibrarySegment.principles,
        _LibrarySegment.assumptions,
      ],
    ),
    (
      l10n.knowledgeLibraryTypeGroupAction,
      const <_LibrarySegment>[
        _LibrarySegment.experiments,
        _LibrarySegment.routines,
      ],
    ),
  ];
  return showAppSheet<_LibrarySegment>(
    context: context,
    title: l10n.knowledgeLibraryTypeTitle,
    subtitle: l10n.knowledgeLibraryTypePickerSubtitle,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) ...[
          if (groupIndex > 0) const SizedBox(height: AppSpacing.s12),
          if (groups[groupIndex].$1 case final label?)
            AppSheetSectionLabel(label),
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < groups[groupIndex].$2.length;
                  index++
                ) ...[
                  _LibraryTypeOptionRow(
                    segment: groups[groupIndex].$2[index],
                    count: counts[groups[groupIndex].$2[index]],
                    selected: groups[groupIndex].$2[index] == selected,
                    onPress: () => Navigator.of(
                      sheetContext,
                    ).pop(groups[groupIndex].$2[index]),
                  ),
                  if (index != groups[groupIndex].$2.length - 1)
                    const AppGroupedDivider(
                      indent: AppSpacing.s12,
                      endIndent: AppSpacing.s12,
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _LibraryTypeOptionRow extends StatelessWidget {
  const _LibraryTypeOptionRow({
    required this.segment,
    required this.count,
    required this.selected,
    required this.onPress,
  });

  final _LibrarySegment segment;
  final int? count;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: _segmentLabel(l10n, segment),
      child: AppTappable(
        selected: selected,
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              AppIconTile(
                icon: _segmentIcon(segment),
                color: selected ? colors.primary : colors.mutedForeground,
                size: AppSpacing.s32,
                iconSize: AppIconSizes.sm,
                radius: AppRadius.sm,
                backgroundOpacity: AppOpacity.subtle,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _segmentLabel(l10n, segment),
                      style: context.labelStyle,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      _segmentDescription(l10n, segment),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              if (count != null)
                Text('$count', style: context.captionLabelStyle),
              const SizedBox(width: AppSpacing.s8),
              SizedBox.square(
                dimension: AppIconSizes.sm,
                child: selected
                    ? Icon(
                        FLucideIcons.check,
                        size: AppIconSizes.sm,
                        color: colors.primary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
