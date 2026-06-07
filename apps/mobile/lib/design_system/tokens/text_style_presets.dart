import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Preset text styles that combine a ForUI typography token with the
/// muted foreground colour. These are the most commonly copy-pasted
/// style expressions in the codebase (43+ occurrences).
///
/// Usage:
/// ```dart
/// // Before:
/// Text(sub, style: typography.xs.copyWith(color: colors.mutedForeground))
/// // After:
/// Text(sub, style: context.captionStyle)
/// ```
extension AppTextStyles on BuildContext {
  /// `typography.xs` + `colors.mutedForeground` — the "caption" style
  /// used for metadata, timestamps, and secondary labels.
  TextStyle get captionStyle =>
      theme.typography.xs.copyWith(color: theme.colors.mutedForeground);

  /// `typography.sm` + `colors.mutedForeground` — the "body caption"
  /// style used for slightly larger secondary text.
  TextStyle get bodyCaptionStyle =>
      theme.typography.sm.copyWith(color: theme.colors.mutedForeground);

  /// `typography.xs2` + `colors.mutedForeground` — the smallest
  /// caption style used for badges and micro-labels.
  TextStyle get microCaptionStyle =>
      theme.typography.xs2.copyWith(color: theme.colors.mutedForeground);
}
