import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';

/// Thin-line Switch that replaces Material's rounded Switch.
///
/// Track: 32x18, thumb: 14. On = emerald, off = neutral 600 + hairline.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // ignore: deprecated_member_use
    return Switch(
      value: value,
      onChanged: enabled ? onChanged : null,
      // ignore: deprecated_member_use
      activeColor: ColorPalette.green500,
      inactiveTrackColor: isDark ? ColorPalette.neutral700 : ColorPalette.neutral300,
      inactiveThumbColor: isDark ? ColorPalette.neutral400 : ColorPalette.neutral500,
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return isDark ? ColorPalette.neutral600 : ColorPalette.neutral400;
      }),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Thin-line Checkbox with 1.5dp border and 4dp radius.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.enabled = true,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Checkbox(
      value: value,
      onChanged: enabled ? onChanged : null,
      tristate: tristate,
      activeColor: ColorPalette.green500,
      checkColor: Colors.white,
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BorderSide.none;
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: isDark ? ColorPalette.neutral700 : ColorPalette.neutral300, width: 1.5);
        }
        return BorderSide(color: isDark ? ColorPalette.neutral500 : ColorPalette.neutral400, width: 1.5);
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Thin-line Radio with 1.5dp outer ring and 8dp inner dot.
class AppRadio<T> extends StatelessWidget {
  const AppRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // ignore: deprecated_member_use
    return Radio<T>(
      value: value,
      // ignore: deprecated_member_use
      groupValue: groupValue,
      // ignore: deprecated_member_use
      onChanged: enabled ? onChanged : null,
      activeColor: ColorPalette.green500,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return ColorPalette.green500;
        if (states.contains(WidgetState.disabled)) {
          return isDark ? ColorPalette.neutral700 : ColorPalette.neutral300;
        }
        return isDark ? ColorPalette.neutral500 : ColorPalette.neutral400;
      }),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
