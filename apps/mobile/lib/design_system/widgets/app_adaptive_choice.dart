import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_adaptive_selection_menu.dart';
import 'app_tappable.dart';
import 'segmented_row.dart';

/// A single-choice control that keeps short choices immediately visible and
/// moves larger semantic taxonomies into the platform-appropriate picker.
///
/// Use this instead of placing four or more long-labelled [SegmentedRow]
/// options in a compact page or form sheet. Phone and tablet surfaces get one
/// stable row plus a touch sheet; wide surfaces keep the faster segmented
/// interaction. Callers may raise [inlineMaxOptions] for compact time ranges.
class AppAdaptiveChoice<T> extends StatelessWidget {
  const AppAdaptiveChoice({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
    this.descriptionOf,
    this.iconOf,
    this.semanticLabelOf,
    this.triggerSubtitle,
    this.inlineMaxOptions = 3,
    this.wideInlineBreakpoint = Breakpoints.readingColumn,
    this.minSegmentWidth = 96,
  }) : assert(options.length > 0),
       assert(inlineMaxOptions > 0);

  final String title;
  final String? subtitle;
  final List<T> options;
  final T value;
  final String Function(T value) labelOf;
  final String? Function(T value)? descriptionOf;
  final IconData? Function(T value)? iconOf;
  final String Function(T value)? semanticLabelOf;
  final ValueChanged<T> onChanged;

  /// Optional second line in the compact trigger, such as a result count.
  final String? triggerSubtitle;

  /// Option counts at or below this threshold remain inline at every width.
  final int inlineMaxOptions;

  /// Four-or-more option sets return inline once this width is available.
  final double wideInlineBreakpoint;
  final double minSegmentWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            options.length <= inlineMaxOptions ||
            constraints.maxWidth >= wideInlineBreakpoint;
        if (inline) {
          return SegmentedRow<T>(
            options: options,
            value: value,
            labelOf: labelOf,
            semanticLabelOf: semanticLabelOf,
            iconOf: iconOf,
            minSegmentWidth: minSegmentWidth,
            onChanged: onChanged,
          );
        }
        return AppAdaptiveSelectionMenu<T>(
          title: title,
          subtitle: subtitle,
          options: [
            for (final option in options)
              AppAdaptiveSelection<T>(
                value: option,
                title: labelOf(option),
                subtitle: descriptionOf?.call(option),
                icon: iconOf?.call(option) ?? FLucideIcons.circle,
              ),
          ],
          value: value,
          onChanged: onChanged,
          triggerBuilder: (context, openMenu, focusNode) => Focus(
            focusNode: focusNode,
            child: _ChoiceTrigger(
              title: labelOf(value),
              subtitle: triggerSubtitle,
              semanticLabel:
                  '$title: ${semanticLabelOf?.call(value) ?? labelOf(value)}',
              icon: iconOf?.call(value),
              onPress: openMenu,
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceTrigger extends StatelessWidget {
  const _ChoiceTrigger({
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.icon,
    required this.onPress,
  });

  final String title;
  final String? subtitle;
  final String semanticLabel;
  final IconData? icon;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: AppTappable(
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s8,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppIconSizes.sm, color: colors.primary),
                    const SizedBox(width: AppSpacing.s8),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.labelStyle,
                        ),
                        if (hasSubtitle) ...[
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.captionStyle,
                          ),
                        ],
                      ],
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
