import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

/// Single-line setting row in iOS-style inset-grouped lists.
///
/// Layout: leading icon · label (Expanded) · trailing value chip · chevron.
/// Tap opens a [_SettingPickerSheet] with the candidate values; the
/// selection is committed via [onChanged]. Replaces the legacy
/// stacked layout (`FSelect` with its label rendered above the field)
/// which doubled the row height for every selector.
///
/// Use [InlineSwitchRow] when the trailing control is an on/off toggle —
/// same row chrome, no popup.
class InlineSettingRow<T> extends StatelessWidget {
  const InlineSettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final T value;
  final Map<String, T> options;
  final ValueChanged<T> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final selectedLabel = options.entries
        .firstWhere(
          (e) => e.value == value,
          orElse: () => MapEntry(value.toString(), value),
        )
        .key;
    return FTappable(
      onPress: () {
        unawaited(_openPicker(context));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.theme.typography.sm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                selectedLabel,
                style: context.theme.typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: colors.mutedForeground.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    unawaited(HapticFeedback.selectionClick());
    final picked = await showFSheet<T>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => _SettingPickerSheet<T>(
        title: label,
        value: value,
        options: options,
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }
}

class _SettingPickerSheet<T> extends StatelessWidget {
  const _SettingPickerSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  final String title;
  final T value;
  final Map<String, T> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colors.mutedForeground.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Text(
              title,
              style: context.theme.typography.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in options.entries) ...[
            FTappable(
              onPress: () => Navigator.of(context).pop(entry.value),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: context.theme.typography.sm,
                      ),
                    ),
                    if (entry.value == value)
                      Icon(Icons.check, size: 18, color: colors.primary),
                  ],
                ),
              ),
            ),
            if (entry.key != options.entries.last.key)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  height: 1,
                  color: colors.foreground.withValues(alpha: 0.05),
                ),
              ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Single-line setting row with a trailing toggle. Same chrome as
/// [InlineSettingRow] so the surrounding section keeps a uniform
/// rhythm.
class InlineSwitchRow extends StatelessWidget {
  const InlineSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.theme.typography.sm),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FSwitch(
            value: value,
            onChange: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Single-line link row (no trailing value chip; just chevron). Same
/// chrome as [InlineSettingRow]. Use for navigation tiles inside an
/// inset-grouped section.
class InlineLinkRow extends StatelessWidget {
  const InlineLinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailingValue,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailingValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: context.theme.typography.sm),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailingValue != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailingValue!,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: colors.mutedForeground.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

