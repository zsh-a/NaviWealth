import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/health_series.dart';
import '../domain/health_metric_kind.dart';
import 'health_metric_colors.dart';

enum HealthChartStyle { line, bars, states }

/// One display vocabulary for Today, Trends, records and period summaries.
extension HealthMetricPresentation on HealthMetricKind {
  IconData get icon => switch (this) {
    HealthMetricKind.sleepSession => FLucideIcons.moon,
    HealthMetricKind.hrvDaily => FLucideIcons.heartPulse,
    HealthMetricKind.rhrDaily ||
    HealthMetricKind.heartRateDaily => FLucideIcons.heart,
    HealthMetricKind.stepsDaily => FLucideIcons.footprints,
    HealthMetricKind.workoutSession => FLucideIcons.dumbbell,
    HealthMetricKind.weight => FLucideIcons.scale,
    HealthMetricKind.bodyFat => FLucideIcons.percent,
    HealthMetricKind.stressDaily => FLucideIcons.brain,
    HealthMetricKind.bodyBatteryDaily => FLucideIcons.battery,
    HealthMetricKind.spo2Daily ||
    HealthMetricKind.respiratoryRateDaily => FLucideIcons.wind,
    HealthMetricKind.distanceWalkingRunningDaily => FLucideIcons.mapPin,
    HealthMetricKind.floorsClimbedDaily => FLucideIcons.trendingUp,
    HealthMetricKind.activeEnergyDaily ||
    HealthMetricKind.totalEnergyDaily => FLucideIcons.flame,
    _ => FLucideIcons.activity,
  };
  Color get accent => switch (group) {
    TrendGroup.recovery => HealthMetricColors.recovery,
    TrendGroup.activity => HealthMetricColors.activity,
    TrendGroup.body => HealthMetricColors.body,
  };
  HealthChartStyle get chartStyle =>
      this == HealthMetricKind.trainingEffectDaily
      ? HealthChartStyle.states
      : isCumulative || this == HealthMetricKind.sleepSession
      ? HealthChartStyle.bars
      : HealthChartStyle.line;

  String title(AppLocalizations l) => switch (this) {
    HealthMetricKind.hrvDaily => l.healthHrvMetricLabel,
    HealthMetricKind.sleepSession => l.healthSleepMetricLabel,
    HealthMetricKind.rhrDaily => l.healthRhrMetricLabel,
    HealthMetricKind.heartRateDaily => l.healthHeartRateMetricLabel,
    HealthMetricKind.stepsDaily => l.healthStepsMetricLabel,
    HealthMetricKind.workoutSession => l.healthWorkoutMetricLabel,
    HealthMetricKind.activeEnergyDaily => l.healthEnergyMetricLabel,
    HealthMetricKind.totalEnergyDaily => l.healthTrendTotalEnergyTitle,
    HealthMetricKind.weight => l.healthMetricWeight,
    HealthMetricKind.bodyFat => l.healthMetricBodyFat,
    HealthMetricKind.vo2Max => l.healthTrendVo2MaxTitle,
    HealthMetricKind.bodyBatteryDaily => l.healthBodyBatteryMetricLabel,
    HealthMetricKind.stressDaily => l.healthStressMetricLabel,
    HealthMetricKind.spo2Daily => l.healthSpo2MetricLabel,
    HealthMetricKind.respiratoryRateDaily => l.healthTrendRespiratoryTitle,
    HealthMetricKind.trainingLoadDaily => l.healthTrainingLoadMetricLabel,
    HealthMetricKind.trainingEffectDaily => l.healthTrendTrainingEffectTitle,
    HealthMetricKind.floorsClimbedDaily => l.healthTrendFlightsTitle,
    HealthMetricKind.distanceWalkingRunningDaily =>
      l.healthTrendWalkingDistanceTitle,
    HealthMetricKind.unknown => l.healthNoData,
  };

  String description(AppLocalizations l) => switch (this) {
    HealthMetricKind.sleepSession => l.healthSleepDailyDefinition,
    HealthMetricKind.bodyBatteryDaily => l.healthTrendBodyBatterySubtitle,
    HealthMetricKind.trainingLoadDaily => l.healthTrendTrainingLoadSubtitle,
    HealthMetricKind.trainingEffectDaily => l.healthTrendTrainingEffectSubtitle,
    HealthMetricKind.activeEnergyDaily => l.healthActiveEnergyDefinition,
    HealthMetricKind.totalEnergyDaily => l.healthTrendTotalEnergySubtitle,
    HealthMetricKind.heartRateDaily => l.healthTrendHeartRateSubtitle,
    HealthMetricKind.rhrDaily => l.healthTrendRhrSubtitle,
    HealthMetricKind.stressDaily => l.healthTrendStressSubtitle,
    HealthMetricKind.spo2Daily => l.healthTrendSpo2Subtitle,
    HealthMetricKind.vo2Max => l.healthTrendVo2MaxSubtitle,
    HealthMetricKind.hrvDaily => l.healthTrendHrvSubtitle,
    _ => l.healthRecordedDaysDefinition,
  };

  String get displayUnit => switch (this) {
    HealthMetricKind.hrvDaily => 'ms',
    HealthMetricKind.rhrDaily || HealthMetricKind.heartRateDaily => 'bpm',
    HealthMetricKind.weight => 'kg',
    HealthMetricKind.bodyFat || HealthMetricKind.spo2Daily => '%',
    HealthMetricKind.activeEnergyDaily ||
    HealthMetricKind.totalEnergyDaily => 'kcal',
    HealthMetricKind.distanceWalkingRunningDaily => 'km',
    HealthMetricKind.respiratoryRateDaily => 'rpm',
    HealthMetricKind.bodyBatteryDaily || HealthMetricKind.stressDaily => '/100',
    HealthMetricKind.vo2Max => 'ml/kg/min',
    _ => '',
  };

  String formatValue(AppLocalizations l, double value, {bool withUnit = true}) {
    if (this == HealthMetricKind.trainingEffectDaily) {
      return switch (value.round()) {
        4 => l.healthTrainingImproving,
        3 => l.healthTrainingProductive,
        2 => l.healthTrainingMaintaining,
        1 => l.healthTrainingRecovery,
        _ => l.healthTrainingStrained,
      };
    }
    if (this == HealthMetricKind.sleepSession ||
        this == HealthMetricKind.workoutSession) {
      final minutes =
          (this == HealthMetricKind.sleepSession ? value * 60 : value).round();
      if (minutes >= 60 && minutes % 60 == 0) {
        return l.healthDurationHours(minutes ~/ 60);
      }
      return minutes >= 60
          ? l.healthWorkoutDurationHoursMinutes(minutes ~/ 60, minutes % 60)
          : l.healthWorkoutDurationMinutes(minutes);
    }
    final digits =
        isMeasurement ||
            this == HealthMetricKind.distanceWalkingRunningDaily ||
            this == HealthMetricKind.vo2Max
        ? 1
        : 0;
    final number = NumberFormat.decimalPatternDigits(
      locale: l.localeName,
      decimalDigits: digits,
    ).format(value);
    return withUnit && displayUnit.isNotEmpty ? '$number $displayUnit' : number;
  }
}

List<HealthMetricKind> healthGroupKinds(TrendGroup group) => [
  // Explicit primary order, followed by the remaining supported metrics.
  ...switch (group) {
    TrendGroup.recovery => [
      HealthMetricKind.hrvDaily,
      HealthMetricKind.sleepSession,
      HealthMetricKind.rhrDaily,
    ],
    TrendGroup.activity => [
      HealthMetricKind.stepsDaily,
      HealthMetricKind.workoutSession,
      HealthMetricKind.activeEnergyDaily,
    ],
    TrendGroup.body => [
      HealthMetricKind.weight,
      HealthMetricKind.bodyFat,
      HealthMetricKind.vo2Max,
    ],
  },
  ...HealthMetricKind.values
      .where((kind) => kind != HealthMetricKind.unknown && kind.group == group)
      .where(
        (kind) => !{
          HealthMetricKind.hrvDaily,
          HealthMetricKind.sleepSession,
          HealthMetricKind.rhrDaily,
          HealthMetricKind.stepsDaily,
          HealthMetricKind.workoutSession,
          HealthMetricKind.activeEnergyDaily,
          HealthMetricKind.weight,
          HealthMetricKind.bodyFat,
          HealthMetricKind.vo2Max,
        }.contains(kind),
      ),
];

String healthGroupLabel(AppLocalizations l, TrendGroup group) =>
    switch (group) {
      TrendGroup.recovery => l.healthTrendGroupRecovery,
      TrendGroup.activity => l.healthTrendGroupActivity,
      TrendGroup.body => l.healthTrendGroupBody,
    };

String healthDateLabel(AppLocalizations l, DateTime day) =>
    DateFormat.MMMd(l.localeName).format(day);
