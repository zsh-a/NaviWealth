import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_interaction.dart';
import 'app_selection_indicator.dart';

/// Shared Forui-based segmented control with a quiet single-surface chrome.
///
/// The single segmented picker for every domain. It replaces three
/// hand-rolled copies that had drifted apart — KnowledgeOS's
/// `KnowledgeSegmentedRow`, OptionsIncome's local `_SegmentedRow`, and
/// the WealthOS perspective toggle — only one of which carried the
/// overflow-safe layout. Material's `SegmentedButton` needs a Material ancestor
/// and breaks inside Forui sheets, so this is the portable replacement.
///
/// Layout: when each segment can be at least [minSegmentWidth] wide the
/// buttons split the row equally. On compact widths or with large dynamic
/// type, segments wrap into an equal-width grid instead of hiding choices in
/// a horizontal scroller. This keeps every option visible and keyboard /
/// screen-reader order identical to visual order.
class SegmentedRow<T> extends StatelessWidget {
  const SegmentedRow({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.semanticLabelOf,
    this.iconOf,
    this.minSegmentWidth = _defaultMinSegmentWidth,
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;

  /// Optional accessible label when the compact visible label is ambiguous.
  /// Defaults to [labelOf].
  final String Function(T)? semanticLabelOf;
  final ValueChanged<T> onChanged;
  final IconData? Function(T)? iconOf;
  final double minSegmentWidth;

  static const double _defaultMinSegmentWidth = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    if (options.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final n = options.length;
        const gap = AppSpacing.s4;
        final maxW = (constraints.maxWidth - AppSpacing.s8).clamp(
          0.0,
          double.infinity,
        );
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final effectiveMinSegmentWidth =
            minSegmentWidth * (textScale < 1 ? 1 : textScale);
        final fits =
            maxW.isFinite &&
            (maxW - gap * (n - 1)) / n >= effectiveMinSegmentWidth;

        final row = Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              _segment(
                context,
                options[i],
                expand: true,
                minWidth: effectiveMinSegmentWidth,
              ),
            ],
          ],
        );

        final maxColumns = maxW.isFinite
            ? ((maxW + gap) / (effectiveMinSegmentWidth + gap)).floor().clamp(
                1,
                n,
              )
            : n;
        // Balance wrapped rows instead of producing an isolated last item.
        // Example: four options with room for at most three become 2×2 rather
        // than 3+1. Five options remain 3+2 because that is already balanced.
        final rows = (n / maxColumns).ceil();
        final columns = (n / rows).ceil().clamp(1, maxColumns);
        final wrappedSegmentWidth = maxW.isFinite
            ? (maxW - gap * (columns - 1)) / columns
            : effectiveMinSegmentWidth;
        final wrapped = Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in options)
              SizedBox(
                width: wrappedSegmentWidth,
                child: _segment(
                  context,
                  option,
                  expand: false,
                  minWidth: wrappedSegmentWidth,
                ),
              ),
          ],
        );

        final surface = DecoratedBox(
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: AppOpacity.whisper),
            borderRadius: BorderRadius.circular(
              fits ? AppRadius.md : AppRadius.lg,
            ),
            border: Border.all(
              color: colors.border.withValues(alpha: AppOpacity.subtle),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: fits
                ? Stack(
                    children: [
                      if (options.indexOf(value) case final selected
                          when selected >= 0)
                        AnimatedPositionedDirectional(
                          duration: AppMotionPolicy.duration(
                            context,
                            Motion.componentChange,
                            role: AppMotionRole.decorative,
                          ),
                          curve: Motion.standardDecelerate,
                          start: selected * ((maxW + gap) / n),
                          width: (maxW - gap * (n - 1)) / n,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(
                                  alpha: AppOpacity.faint,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                          ),
                        ),
                      row,
                    ],
                  )
                : wrapped,
          ),
        );

        return surface;
      },
    );
  }

  Widget _segment(
    BuildContext context,
    T option, {
    required bool expand,
    required double minWidth,
  }) {
    final colors = context.theme.colors;
    final icon = iconOf?.call(option);
    final selected = option == value;
    final foreground = selected ? colors.primary : colors.mutedForeground;
    final label = labelOf(option);
    final semanticLabel = semanticLabelOf?.call(option) ?? label;
    final duration = AppMotionPolicy.duration(
      context,
      Motion.fast,
      role: AppMotionRole.decorative,
    );

    final content = AnimatedDefaultTextStyle(
      duration: duration,
      curve: Motion.standard,
      style: (selected ? context.labelStyle : context.mediumLabelStyle)
          .copyWith(color: foreground),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSizes.sm, color: foreground),
            const SizedBox(width: AppSpacing.s6),
          ],
          Flexible(
            fit: expand ? FlexFit.tight : FlexFit.loose,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );

    final segment = Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      onTap: () => _select(option),
      excludeSemantics: true,
      child: FTappable(
        onPress: () => _select(option),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppControlHeights.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              if (!expand) ...[
                const SizedBox(height: AppSpacing.s2),
                AppSelectionIndicator(
                  selected: selected,
                  length: AppSpacing.s16,
                  thickness: AppSpacing.s2,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return expand
        ? Expanded(child: segment)
        : ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: segment,
          );
  }

  void _select(T option) {
    if (option == value) return;
    AppInteraction.signal(AppInteractionIntent.select);
    onChanged(option);
  }
}
