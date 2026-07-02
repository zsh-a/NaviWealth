part of 'health_trend_page.dart';

class _TrendSpec {
  const _TrendSpec({
    required this.title,
    required this.subtitle,
    required this.kind,
    this.icon,
    this.color,
  });

  final String title;
  final String subtitle;
  final HealthMetricKind kind;
  final IconData? icon;
  final Color? color;
}

List<_TrendSpec> _trendSpecs(AppLocalizations l10n, TrendGroup group) =>
    switch (group) {
      TrendGroup.recovery => [
        _TrendSpec(
          title: l10n.healthHrvMetricLabel,
          subtitle: l10n.healthTrendHrvSubtitle,
          kind: HealthMetricKind.hrvDaily,
          icon: FLucideIcons.heartPulse,
          color: HealthMetricColors.hrv,
        ),
        _TrendSpec(
          title: l10n.healthSleepMetricLabel,
          subtitle: l10n.healthTrendSleepSubtitle,
          kind: HealthMetricKind.sleepSession,
          icon: FLucideIcons.moon,
          color: HealthMetricColors.sleep,
        ),
        _TrendSpec(
          title: l10n.healthHeartRateMetricLabel,
          subtitle: l10n.healthTrendHeartRateSubtitle,
          kind: HealthMetricKind.heartRateDaily,
          icon: FLucideIcons.heart,
          color: HealthMetricColors.heartRate,
        ),
        _TrendSpec(
          title: l10n.healthTrendRhrTitle,
          subtitle: l10n.healthTrendRhrSubtitle,
          kind: HealthMetricKind.rhrDaily,
          icon: FLucideIcons.heart,
          color: HealthMetricColors.rhr,
        ),
        _TrendSpec(
          title: l10n.healthTrendSpo2Title,
          subtitle: l10n.healthTrendSpo2Subtitle,
          kind: HealthMetricKind.spo2Daily,
          icon: FLucideIcons.wind,
          color: HealthMetricColors.spo2,
        ),
        _TrendSpec(
          title: l10n.healthTrendRespiratoryTitle,
          subtitle: l10n.healthTrendRespiratorySubtitle,
          kind: HealthMetricKind.respiratoryRateDaily,
          icon: FLucideIcons.wind,
          color: HealthMetricColors.respiratoryRate,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyBatteryTitle,
          subtitle: l10n.healthTrendBodyBatterySubtitle,
          kind: HealthMetricKind.bodyBatteryDaily,
          icon: FLucideIcons.battery,
          color: HealthMetricColors.bodyBattery,
        ),
        _TrendSpec(
          title: l10n.healthTrendStressTitle,
          subtitle: l10n.healthTrendStressSubtitle,
          kind: HealthMetricKind.stressDaily,
          icon: FLucideIcons.brain,
          color: HealthMetricColors.stress,
        ),
      ],
      TrendGroup.activity => [
        _TrendSpec(
          title: l10n.healthWorkoutMetricLabel,
          subtitle: l10n.healthTrendWorkoutSubtitle,
          kind: HealthMetricKind.workoutSession,
          icon: FLucideIcons.dumbbell,
          color: HealthMetricColors.workout,
        ),
        _TrendSpec(
          title: l10n.healthStepsMetricLabel,
          subtitle: l10n.healthTrendStepsSubtitle,
          kind: HealthMetricKind.stepsDaily,
          icon: FLucideIcons.footprints,
          color: HealthMetricColors.steps,
        ),
        _TrendSpec(
          title: l10n.healthEnergyMetricLabel,
          subtitle: l10n.healthTrendTotalEnergySubtitle,
          kind: HealthMetricKind.activeEnergyDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.totalEnergy,
        ),
        _TrendSpec(
          title: l10n.healthTrendWalkingDistanceTitle,
          subtitle: l10n.healthTrendWalkingDistanceSubtitle,
          kind: HealthMetricKind.distanceWalkingRunningDaily,
          icon: FLucideIcons.mapPin,
          color: HealthMetricColors.walkingDistance,
        ),
        _TrendSpec(
          title: l10n.healthTrendFlightsTitle,
          subtitle: l10n.healthTrendFlightsSubtitle,
          kind: HealthMetricKind.floorsClimbedDaily,
          icon: FLucideIcons.trendingUp,
          color: HealthMetricColors.floors,
        ),
        _TrendSpec(
          title: l10n.healthTrendTrainingLoadTitle,
          subtitle: l10n.healthTrendTrainingLoadSubtitle,
          kind: HealthMetricKind.trainingLoadDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.trainingLoad,
        ),
        _TrendSpec(
          title: l10n.healthTrendTrainingEffectTitle,
          subtitle: l10n.healthTrendTrainingEffectSubtitle,
          kind: HealthMetricKind.trainingEffectDaily,
          icon: FLucideIcons.zap,
          color: HealthMetricColors.trainingEffect,
        ),
        _TrendSpec(
          title: l10n.healthTrendTotalEnergyTitle,
          subtitle: l10n.healthTrendTotalEnergySubtitle,
          kind: HealthMetricKind.totalEnergyDaily,
          icon: FLucideIcons.flame,
          color: HealthMetricColors.totalEnergy,
        ),
      ],
      TrendGroup.body => [
        _TrendSpec(
          title: l10n.healthTrendWeightTitle,
          subtitle: l10n.healthTrendWeightSubtitle,
          kind: HealthMetricKind.weight,
          icon: FLucideIcons.scale,
          color: HealthMetricColors.weight,
        ),
        _TrendSpec(
          title: l10n.healthTrendBodyFatTitle,
          subtitle: l10n.healthTrendBodyFatSubtitle,
          kind: HealthMetricKind.bodyFat,
          icon: FLucideIcons.percent,
          color: HealthMetricColors.bodyFat,
        ),
        _TrendSpec(
          title: l10n.healthTrendVo2MaxTitle,
          subtitle: l10n.healthTrendVo2MaxSubtitle,
          kind: HealthMetricKind.vo2Max,
          icon: FLucideIcons.activity,
          color: HealthMetricColors.vo2Max,
        ),
      ],
    };

/// Kinds for a group, used by the batch provider (no l10n needed).
List<_TrendSpec> _trendSpecsRaw(TrendGroup group) => switch (group) {
  TrendGroup.recovery => [
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.hrvDaily),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.sleepSession,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.heartRateDaily,
    ),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.rhrDaily),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.spo2Daily),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.respiratoryRateDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.bodyBatteryDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.stressDaily,
    ),
  ],
  TrendGroup.activity => [
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.workoutSession,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.stepsDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.activeEnergyDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.distanceWalkingRunningDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.floorsClimbedDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.trainingLoadDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.trainingEffectDaily,
    ),
    const _TrendSpec(
      title: '',
      subtitle: '',
      kind: HealthMetricKind.totalEnergyDaily,
    ),
  ],
  TrendGroup.body => [
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.weight),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.bodyFat),
    const _TrendSpec(title: '', subtitle: '', kind: HealthMetricKind.vo2Max),
  ],
};
