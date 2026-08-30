import 'package:flutter/widgets.dart';

import 'package:naviwealth/design_system/design_system.dart';

import '../domain/fire_action.dart';
import '../domain/fire_state.dart';
import '../domain/fire_stress_test.dart';

/// Maps FIRE domain enums to [AppThemeData] status roles so UI files
/// share one resolution path instead of each hardcoding Material palette
/// names.
Color fireSafetyColor(AppThemeData theme, FireSafetyLevel level) {
  switch (level) {
    case FireSafetyLevel.safe:
      return theme.status.success.fg;
    case FireSafetyLevel.cautious:
      return theme.status.warning.fg;
    case FireSafetyLevel.danger:
      return theme.status.danger.fg;
    case FireSafetyLevel.unconfigured:
      return theme.surfaces.border;
  }
}

Color fireActionSeverityColor(AppThemeData theme, FireActionSeverity severity) {
  switch (severity) {
    case FireActionSeverity.info:
      return theme.status.info.fg;
    case FireActionSeverity.warning:
      return theme.status.warning.fg;
    case FireActionSeverity.critical:
      return theme.status.danger.fg;
  }
}

Color fireStressVerdictColor(AppThemeData theme, FireStressVerdict verdict) {
  switch (verdict) {
    case FireStressVerdict.safe:
      return theme.status.success.fg;
    case FireStressVerdict.cautious:
      return theme.status.warning.fg;
    case FireStressVerdict.danger:
      return theme.status.danger.fg;
  }
}
