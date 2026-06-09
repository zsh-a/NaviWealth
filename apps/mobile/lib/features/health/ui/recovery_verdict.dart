/// Shared recovery verdict presentation helpers for HealthOS.
///
/// Maps the raw verdict string (`rested` / `balanced` / `strained` /
/// `insufficient_data`) to icon, color, label, and suggestion text.
/// Used by both the Today page (_RecoveryHero) and the Plan page
/// (_RecoveryCard) so the visual language stays consistent.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';

abstract final class RecoveryVerdict {
  const RecoveryVerdict._();

  /// Icon representing the verdict state.
  static IconData icon(String verdict) => switch (verdict) {
    'rested' => FLucideIcons.zap,
    'balanced' => FLucideIcons.scale,
    'strained' => FLucideIcons.triangleAlert,
    _ => FLucideIcons.circleHelp,
  };

  /// Accent color for the verdict.
  static Color color(String verdict, FColors colors) => switch (verdict) {
    'rested' => colors.primary,
    'balanced' => colors.mutedForeground,
    'strained' => colors.destructive,
    _ => colors.mutedForeground,
  };

  /// Human-readable verdict label (e.g. "Rested", "Balanced").
  static String label(String verdict, AppLocalizations l10n) =>
      switch (verdict) {
        'rested' => l10n.healthRecoveryRested,
        'balanced' => l10n.healthRecoveryBalanced,
        'strained' => l10n.healthRecoveryStrained,
        _ => l10n.healthRecoveryInsufficient,
      };

  /// Short suggestion text keyed off the verdict.
  static String suggestion(String verdict, AppLocalizations l10n) =>
      switch (verdict) {
        'rested' => l10n.healthRecoveryRestedTip,
        'balanced' => l10n.healthRecoveryBalancedTip,
        'strained' => l10n.healthRecoveryStrainedTip,
        _ => l10n.healthRecoveryInsufficientTip,
      };
}
