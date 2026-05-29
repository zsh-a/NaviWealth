/// Forui-based segmented control reused across KnowledgeOS UI.
///
/// Mirrors the local `_SegmentedRow` in
/// `features/options_income/presentation/trade_journal_sheet.dart`: a
/// row of equal-width `FButton`s where the selected one is
/// `primary` and the rest are `outline`. Material's `SegmentedButton`
/// needs a Material ancestor and breaks inside Forui sheets, so this
/// file replaces it everywhere KnowledgeOS needs a segmented picker.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';

class KnowledgeSegmentedRow<T> extends StatelessWidget {
  const KnowledgeSegmentedRow({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// Below this comfortable per-segment width the equal-split Row would
  /// clip labels (e.g. 5 segments on a 360-dp phone). At/under it we fall
  /// back to a horizontally scrollable row of intrinsic-width buttons so
  /// text never overflows.
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
        // Equal-width fill when there's room; otherwise scroll horizontally
        // so every label stays legible on a narrow screen.
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
    final button = FButton(
      variant: option == value
          ? FButtonVariant.primary
          : FButtonVariant.outline,
      onPress: () => onChanged(option),
      child: Text(
        labelOf(option),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return expand ? Expanded(child: button) : button;
  }
}
