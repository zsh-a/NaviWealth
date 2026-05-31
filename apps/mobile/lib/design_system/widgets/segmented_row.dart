import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Shared Forui-based segmented control: a row of equal-width `FButton`s
/// where the selected option is `primary` and the rest are `outline`.
///
/// The single segmented picker for every domain. It replaces three
/// hand-rolled copies that had drifted apart — KnowledgeOS's
/// `KnowledgeSegmentedRow`, OptionsIncome's local `_SegmentedRow`, and
/// the WealthOS perspective toggle — only one of which carried the
/// overflow-safe layout. Material's `SegmentedButton` needs a Material
/// ancestor and breaks inside Forui sheets, so this is the portable
/// replacement.
///
/// Layout: when each segment can be at least [_minSegmentWidth] wide the
/// buttons split the row equally (labels ellipsize within their slot —
/// FButton lays its child in a `MainAxisSize.max` Row without a Flexible,
/// so the wrap below is what stops a wide label from overflowing). Below
/// that the row falls back to a horizontally scrollable strip of
/// intrinsic-width buttons so labels stay legible on narrow screens.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = options.length;
        const gap = AppSpacing.s8;
        final maxW = constraints.maxWidth;
        final fits =
            maxW.isFinite && (maxW - gap * (n - 1)) / n >= _minSegmentWidth;

        final children = <Widget>[];
        for (var i = 0; i < n; i++) {
          if (i > 0) children.add(const SizedBox(width: gap));
          children.add(_button(options[i], expand: fits));
        }

        final row = Row(
          mainAxisSize: fits ? MainAxisSize.max : MainAxisSize.min,
          children: children,
        );
        return fits
            ? row
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: row,
              );
      },
    );
  }

  Widget _button(T option, {required bool expand}) {
    final icon = iconOf?.call(option);
    final label = Text(
      labelOf(option),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final button = FButton(
      variant: option == value
          ? FButtonVariant.primary
          : FButtonVariant.outline,
      onPress: () => onChanged(option),
      prefix: icon == null ? null : Icon(icon, size: AppIconSizes.sm),
      // In the equal-split (expand) layout the button has a bounded width,
      // but FButton lays its child in a `MainAxisSize.max` Row without a
      // Flexible — so a label wider than the slot overflows instead of
      // ellipsizing. Wrap it so it shrinks to fit. The scroll fallback
      // keeps the bare Text: there the Row is unbounded and a Flexible
      // would assert.
      child: expand ? Flexible(child: label) : label,
    );
    return expand ? Expanded(child: button) : button;
  }
}
