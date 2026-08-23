import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../attention_item.dart';

/// Dense, section-level presentation for concrete attention items.
///
/// Repeated items are flat rows inside one surface. The item count appears
/// once in the section header and details are progressively disclosed in a
/// sheet, avoiding the summary/metric/insight repetition of Agent cards.
class AttentionGroup extends StatelessWidget {
  const AttentionGroup({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.subtitle,
    this.maxVisibleItems,
  });

  final String title;
  final String? subtitle;
  final List<AttentionItem> items;
  final ValueChanged<AttentionItem> onOpen;
  final int? maxVisibleItems;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cap = maxVisibleItems;
    final visible = cap == null
        ? items
        : items.take(cap).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.module(
          title: title,
          subtitle: subtitle,
          trailing: AppBadge(
            label: '${items.length}',
            size: AppBadgeSize.compact,
            tone:
                items.any(
                  (item) => item.severity == AttentionItemSeverity.warning,
                )
                ? AppBadgeTone.warning
                : AppBadgeTone.accent,
          ),
        ),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                _AttentionRow(
                  item: visible[index],
                  onPress: () => onOpen(visible[index]),
                ),
                if (index != visible.length - 1)
                  const AppGroupedDivider(indent: AppSpacing.s48),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.onPress});

  final AttentionItem item;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final status = context.appTheme.status;
    final accent = switch (item.severity) {
      AttentionItemSeverity.info => status.info.fg,
      AttentionItemSeverity.attention => colors.primary,
      AttentionItemSeverity.warning => status.warning.fg,
    };
    return Semantics(
      button: true,
      label: item.headline,
      child: AppTappable(
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: const SizedBox(width: AppSpacing.s4, height: 28),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.headline,
                      style: context.labelStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      item.rationale,
                      style: context.captionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.facts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Wrap(
                        spacing: AppSpacing.s6,
                        runSpacing: AppSpacing.s4,
                        children: [
                          for (final fact in item.facts.take(2))
                            AppBadge(
                              label: '${fact.label} ${fact.value}',
                              size: AppBadgeSize.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s4),
                child: Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAttentionItemSheet({
  required BuildContext context,
  required AttentionItem item,
  required String evidenceTitle,
  required String actionLabel,
  required VoidCallback onAction,
}) {
  return showAppSheet<void>(
    context: context,
    title: item.headline,
    subtitle: item.rationale,
    footer: Builder(
      builder: (sheetContext) => SafeArea(
        top: false,
        child: FButton(
          onPress: () => closeSheetThen(sheetContext, onAction),
          child: Text(actionLabel),
        ),
      ),
    ),
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.facts.isNotEmpty)
          AppMetricCluster(
            dense: true,
            items: [
              for (final fact in item.facts.take(3))
                AppMetricItem(label: fact.label, value: fact.value),
            ],
          ),
        if (item.facts.isNotEmpty && item.evidence.isNotEmpty)
          const SizedBox(height: AppSpacing.s20),
        if (item.evidence.isNotEmpty) ...[
          Text(evidenceTitle, style: sheetContext.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          AppGroupedSurface(
            child: Column(
              children: [
                for (var index = 0; index < item.evidence.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          FLucideIcons.database,
                          size: AppIconSizes.sm,
                          color: sheetContext.theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: AppSpacing.s10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.evidence[index].label,
                                style: sheetContext.labelStyle,
                              ),
                              if (item.evidence[index].detail != null) ...[
                                const SizedBox(height: AppSpacing.s2),
                                Text(
                                  item.evidence[index].detail!,
                                  style: sheetContext.captionStyle,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index != item.evidence.length - 1)
                    const AppGroupedDivider(indent: AppSpacing.s32),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
