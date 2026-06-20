import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/motion_utils.dart';
import '../tokens/text_style_presets.dart';

/// Shared Forui-based segmented control with a quiet single-surface chrome.
///
/// The single segmented picker for every domain. It replaces three
/// hand-rolled copies that had drifted apart — KnowledgeOS's
/// `KnowledgeSegmentedRow`, OptionsIncome's local `_SegmentedRow`, and
/// the WealthOS perspective toggle — only one of which carried the
/// overflow-safe layout. Material's `SegmentedButton` needs a Material ancestor
/// and breaks inside Forui sheets, so this is the portable replacement.
///
/// Layout: when each segment can be at least [_minSegmentWidth] wide the
/// buttons split the row equally (labels ellipsize within their slot —
/// the scroll fallback keeps intrinsic-width labels legible on narrow screens).
/// Below that the row falls back to a horizontally scrollable strip.
class SegmentedRow<T> extends StatelessWidget {
  const SegmentedRow({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final IconData? Function(T)? iconOf;

  static const double _minSegmentWidth = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final n = options.length;
        const gap = AppSpacing.s4;
        final maxW = constraints.maxWidth;
        final fits =
            maxW.isFinite && (maxW - gap * (n - 1)) / n >= _minSegmentWidth;

        final children = <Widget>[];
        for (var i = 0; i < n; i++) {
          if (i > 0) children.add(const SizedBox(width: gap));
          children.add(_segment(context, options[i], expand: fits));
        }

        final row = Row(
          mainAxisSize: fits ? MainAxisSize.max : MainAxisSize.min,
          children: children,
        );

        final surface = DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: AppOpacity.disabled),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: colors.border.withValues(alpha: AppOpacity.highlight),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: fits
                ? row
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: row,
                  ),
          ),
        );

        return fits
            ? surface
            : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: surface,
              );
      },
    );
  }

  Widget _segment(BuildContext context, T option, {required bool expand}) {
    final colors = context.theme.colors;
    final icon = iconOf?.call(option);
    final selected = option == value;
    final foreground = selected ? colors.foreground : colors.mutedForeground;
    final label = labelOf(option);
    final duration = motionDuration(context, Motion.fast);

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
      label: label,
      child: FTappable(
        onPress: () => onChanged(option),
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.standard,
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.background
                : colors.background.withValues(alpha: AppOpacity.transparent),
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: selected ? AppShadow.elevation1 : const [],
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    return expand
        ? Expanded(child: segment)
        : ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minSegmentWidth),
            child: segment,
          );
  }
}
