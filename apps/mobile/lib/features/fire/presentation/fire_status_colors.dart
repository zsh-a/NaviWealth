import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../domain/fire_action.dart';
import '../domain/fire_bucket.dart';
import '../domain/fire_state.dart';
import '../domain/fire_stress_test.dart';

/// Maps FIRE domain enums to [SemanticColors] so presentation files
/// share one resolution path instead of each hardcoding Material palette
/// names.
Color fireSafetyColor(SemanticColors sem, FireSafetyLevel level) {
  switch (level) {
    case FireSafetyLevel.safe:
      return sem.success;
    case FireSafetyLevel.cautious:
      return sem.warning;
    case FireSafetyLevel.danger:
      return sem.danger;
    case FireSafetyLevel.unconfigured:
      return sem.divider;
  }
}

Color fireBucketStatusColor(
  SemanticColors sem,
  FColors colors,
  FireBucketStatus status,
) {
  switch (status) {
    case FireBucketStatus.onTrack:
      return sem.success;
    case FireBucketStatus.underTarget:
      return sem.warning;
    case FireBucketStatus.overTarget:
      return sem.info;
    case FireBucketStatus.empty:
      return colors.mutedForeground;
  }
}

Color fireActionSeverityColor(SemanticColors sem, FireActionSeverity severity) {
  switch (severity) {
    case FireActionSeverity.info:
      return sem.info;
    case FireActionSeverity.warning:
      return sem.warning;
    case FireActionSeverity.critical:
      return sem.danger;
  }
}

Color fireStressVerdictColor(SemanticColors sem, FireStressVerdict verdict) {
  switch (verdict) {
    case FireStressVerdict.safe:
      return sem.success;
    case FireStressVerdict.cautious:
      return sem.warning;
    case FireStressVerdict.danger:
      return sem.danger;
  }
}
