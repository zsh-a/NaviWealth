import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
import 'app_ink_well.dart';
import 'glass_modal_bottom_sheet.dart';
import 'liquid_glass_card.dart';

/// Glass-style dropdown that opens a [showGlassModalBottomSheet] for selection.
///
/// Replaces Material [DropdownButtonFormField] with a visual treatment
/// consistent with the app's glass design language: the trigger is a
/// [LiquidGlassCard] (tertiary layer), and the picker opens as a glass
/// bottom sheet matching other modals in the app.
///
/// Accepts [DropdownMenuItem] lists for backward compatibility with
/// existing form code.
///
/// Usage:
/// ```dart
/// AppDropdown<AccountType>(
///   label: 'Account Type',
///   value: _type,
///   items: [
///     for (final t in AccountType.values)
///       DropdownMenuItem(value: t, child: Text(labelOf(t))),
///   ],
///   onChanged: (v) => setState(() => _type = v),
/// )
/// ```
class AppDropdown<T> extends FormField<T> {
  AppDropdown({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.label,
    this.helperText,
    super.enabled,
    super.validator,
    this.displayBuilder,
  }) : super(
          initialValue: value,
          builder: (field) {
            final state = field as _AppDropdownState<T>;
            return state._buildField();
          },
        );

  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? helperText;

  /// Optional custom builder for the trigger display text.
  /// When null, the matching [DropdownMenuItem]'s child is used.
  final Widget Function(BuildContext context, T? value)? displayBuilder;

  @override
  FormFieldState<T> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends FormFieldState<T> {
  @override
  AppDropdown<T> get widget => super.widget as AppDropdown<T>;

  @override
  void didUpdateWidget(AppDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != value) {
      // Defer to after the current build to avoid calling Form.setState
      // during the build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) didChange(widget.value);
      });
    }
  }

  void _openPicker() {
    if (!widget.enabled) return;
    showGlassModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _PickerSheet<T>(
        items: widget.items,
        selectedValue: value,
        label: widget.label,
        onSelected: (v) {
          didChange(v);
          widget.onChanged?.call(v);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Widget _buildField() {
    final theme = Theme.of(context);
    final hasError = errorText != null;
    final effectiveEnabled = widget.enabled;

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: hasError
          ? ColorPalette.red500
          : effectiveEnabled
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    // Find the selected item's child for trigger display.
    Widget? displayChild;
    if (widget.displayBuilder != null) {
      displayChild = widget.displayBuilder!(context, value);
    } else if (value != null) {
      for (final item in widget.items) {
        if (item.value == value) {
          displayChild = item.child;
          break;
        }
      }
    }

    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: effectiveEnabled
          ? null
          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );

    final trigger = LiquidGlassCard(
      layer: GlassLayer.tertiary,
      borderRadius: Radii.lg.toDouble(),
      onTap: effectiveEnabled ? _openPicker : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: displayChild != null
                  ? DefaultTextStyle(style: valueStyle!, child: displayChild)
                  : Text(
                      '',
                      style: valueStyle?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: effectiveEnabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: effectiveEnabled ? _openPicker : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(widget.label!, style: labelStyle),
            const SizedBox(height: Spacing.s4),
          ],
          trigger,
          if (widget.helperText != null && !hasError) ...[
            const SizedBox(height: Spacing.s4),
            Text(
              widget.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (hasError) ...[
            const SizedBox(height: Spacing.s4),
            Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ColorPalette.red500,
              ),
            ),
          ],
        ],
    ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.label,
  });

  final List<DropdownMenuItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Spacing.s12),
          // Drag handle.
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: Radii.brXxl,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: Spacing.s16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
              child: Text(
                label!,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
          const SizedBox(height: Spacing.s12),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Spacing.s16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final isSelected = item.value == selectedValue;
                return AppInkWell(
                  onTap: () => onSelected(item.value as T),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.s16,
                      vertical: Spacing.s12,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: item.child),
                        if (isSelected)
                          const Icon(
                            Icons.check,
                            size: 20,
                            color: ColorPalette.green500,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
