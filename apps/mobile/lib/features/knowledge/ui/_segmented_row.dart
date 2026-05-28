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

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      if (i > 0) children.add(const SizedBox(width: AppSpacing.s8));
      final option = options[i];
      children.add(
        Expanded(
          child: FButton(
            variant: option == value
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () => onChanged(option),
            child: Text(
              labelOf(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    return Row(children: children);
  }
}
