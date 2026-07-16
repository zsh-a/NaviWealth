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
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s2),
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
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

/// Horizontally scrollable tab bar for the 7 Library segments. Every
/// segment keeps its label visible; icon-only tabs made the object
/// families hard to recognize unless the user already knew the order.
class _LibraryTabBar extends StatelessWidget {
  const _LibraryTabBar({required this.selected, required this.onChanged});

  final _LibrarySegment selected;
  final ValueChanged<_LibrarySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<_LibrarySegment>(
      options: _LibrarySegment.values,
      value: selected,
      labelOf: (segment) => _segmentLabel(l10n, segment),
      iconOf: _segmentIcon,
      onChanged: (segment) {
        AppInteraction.signal(AppInteractionIntent.select);
        onChanged(segment);
      },
      minSegmentWidth: 72,
    );
  }
}
