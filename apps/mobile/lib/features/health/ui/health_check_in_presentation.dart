import '../../../l10n/gen/app_localizations.dart';
import '../domain/health_check_in.dart';

String healthEventTagLabel(AppLocalizations l, String tag) {
  final known = HealthEventTag.values
      .where((value) => value.wire == tag)
      .firstOrNull;
  return switch (known) {
    HealthEventTag.caffeine => l.healthTagCaffeine,
    HealthEventTag.lateMeal => l.healthTagLateMeal,
    HealthEventTag.alcohol => l.healthTagAlcohol,
    HealthEventTag.illness => l.healthTagIllness,
    HealthEventTag.travel => l.healthTagTravel,
    HealthEventTag.hardWorkout => l.healthTagHardWorkout,
    HealthEventTag.meditation => l.healthTagMeditation,
    HealthEventTag.lateScreen => l.healthTagLateScreen,
    null => tag,
  };
}

String healthCheckInFeelings(AppLocalizations l, HealthCheckIn entry) => [
  if (entry.energy case final value?)
    l.healthCheckInValue(l.healthCheckInEnergy, value),
  if (entry.sleepQuality case final value?)
    l.healthCheckInValue(l.healthCheckInSleepQuality, value),
  if (entry.stress case final value?)
    l.healthCheckInValue(l.healthCheckInStress, value),
].join(' · ');
