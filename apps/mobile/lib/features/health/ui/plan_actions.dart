import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/gen/app_localizations.dart';

/// Deterministic same-day guidance rows derived from recovery verdict.
/// Shared by the Today hero (primary surface) after Plan tab merge.
class HealthPlanAction {
  const HealthPlanAction({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

List<HealthPlanAction> healthPlanActionsForVerdict(
  String verdict,
  AppLocalizations l10n,
) {
  return switch (verdict) {
    'rested' => [
      HealthPlanAction(
        icon: FLucideIcons.dumbbell,
        text: l10n.healthPlanHighIntensity,
      ),
      HealthPlanAction(icon: FLucideIcons.moon, text: l10n.healthPlanKeepSleep),
    ],
    'balanced' => [
      HealthPlanAction(
        icon: FLucideIcons.activity,
        text: l10n.healthPlanTrainAsPlanned,
      ),
      HealthPlanAction(
        icon: FLucideIcons.coffee,
        text: l10n.healthPlanReduceCaffeine,
      ),
    ],
    'strained' => [
      HealthPlanAction(
        icon: FLucideIcons.footprints,
        text: l10n.healthPlanLightActivity,
      ),
      HealthPlanAction(
        icon: FLucideIcons.calendarX,
        text: l10n.healthPlanAvoidPressure,
      ),
    ],
    _ => [
      HealthPlanAction(
        icon: FLucideIcons.refreshCw,
        text: l10n.healthPlanSyncFirst,
      ),
      HealthPlanAction(
        icon: FLucideIcons.calendarDays,
        text: l10n.healthPlanTrackMore,
      ),
    ],
  };
}
