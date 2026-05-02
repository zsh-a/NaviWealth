import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';

/// [ChoiceChip] wrapper that fires [Haptics.selection] when the chip's
/// selected state changes. Mirrors the slimmest subset of `ChoiceChip`'s
/// constructor — extend as call sites require.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
    this.tooltip,
    this.visualDensity,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final String? tooltip;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: label,
      selected: selected,
      avatar: avatar,
      tooltip: tooltip,
      visualDensity: visualDensity,
      onSelected: onSelected == null
          ? null
          : (value) {
              Haptics.selection();
              onSelected!(value);
            },
    );
  }
}
