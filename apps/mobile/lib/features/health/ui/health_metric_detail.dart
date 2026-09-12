import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_metric_source.dart';
import '../data/health_series.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'body_measurement_entry_sheet.dart';
import 'health_metric_presentation.dart';
import 'health_series_chart.dart';

class HealthMetricDetail extends StatefulWidget {
  const HealthMetricDetail({super.key, required this.series});
  final HealthSeries series;
  @override
  State<HealthMetricDetail> createState() => _HealthMetricDetailState();
}

class _HealthMetricDetailState extends State<HealthMetricDetail> {
  HealthDaySample? _focused;
  bool _showAll = false;
  @override
  void didUpdateWidget(covariant HealthMetricDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) _focused = null;
    if (oldWidget.series.kind != widget.series.kind) _showAll = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final series = widget.series;
    final kind = series.kind;
    final sample = _focused ?? series.latest;
    if (sample == null) {
      return AppEmptyState(
        icon: kind.icon,
        title: l.healthNoData,
        message: l.healthNoRecordsInWindow,
        compact: true,
        action: kind.isMeasurement
            ? FButton(
                onPress: () => showBodyMeasurementEntrySheet(
                  context: context,
                  initialKind: kind,
                ),
                child: Text(l.healthRecordBodyMetricAction),
              )
            : null,
      );
    }
    final records = series.samples.reversed.toList();
    final visible = _showAll ? records : records.take(7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard.raised(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kind.description(l), style: context.captionStyle),
              const SizedBox(height: AppSpacing.s12),
              Text(
                kind.formatValue(l, sample.value),
                style: context.strongTitleStyle,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '${healthDateLabel(l, sample.day)}${kind.isCumulative && sample.day == series.window.today ? ' · ${l.healthTodaySoFar}' : ''}',
                style: context.captionStyle,
              ),
              if (series.samples.length > 1) ...[
                const SizedBox(height: AppSpacing.s16),
                SizedBox(
                  height: kind.chartStyle == HealthChartStyle.states
                      ? null
                      : AppChartHeights.full,
                  child: HealthSeriesChart(
                    series: series,
                    onFocus: (sample) {
                      if (_focused != sample) setState(() => _focused = sample);
                    },
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s12,
                runSpacing: AppSpacing.s8,
                children: [
                  Text(
                    l.healthObservedDayAverage(
                      series.recordedDays,
                      series.window.days,
                    ),
                    style: context.captionStyle,
                  ),
                  if (series.samples.length > 1 &&
                      kind.chartStyle != HealthChartStyle.states)
                    Text(
                      l.healthPeriodAverage(
                        kind.formatValue(l, series.average!),
                      ),
                      style: context.captionStyle,
                    ),
                  if (series.samples.length > 1 && kind.isCumulative)
                    Text(
                      l.healthPeriodTotal(kind.formatValue(l, series.total)),
                      style: context.captionStyle,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                series.samples.length == 1
                    ? l.healthSingleDayHint
                    : l.healthMissingDataDefinition,
                style: context.microCaptionStyle,
              ),
              if (series.changePercent case final double delta) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l.healthPeriodChange(
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
                    series.window.days,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        Text(l.healthRecordsTitle, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, day) in visible.indexed) ...[
                if (index > 0)
                  const AppGroupedDivider(
                    indent: AppSpacing.s16,
                    endIndent: AppSpacing.s16,
                  ),
                _RecordDay(
                  key: ValueKey('${kind.wire}:${day.day}'),
                  kind: kind,
                  sample: day,
                ),
              ],
            ],
          ),
        ),
        if (records.length > 7) ...[
          const SizedBox(height: AppSpacing.s8),
          AppRevealControl(
            expanded: _showAll,
            collapsedLabel: l.commonRevealMore(records.length - 7),
            expandedLabel: l.commonRevealLess,
            onToggle: () => setState(() => _showAll = !_showAll),
          ),
        ],
      ],
    );
  }
}

class _RecordDay extends StatefulWidget {
  const _RecordDay({super.key, required this.kind, required this.sample});
  final HealthMetricKind kind;
  final HealthDaySample sample;
  @override
  State<_RecordDay> createState() => _RecordDayState();
}

class _RecordDayState extends State<_RecordDay> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = widget.kind;
    final sample = widget.sample;
    final sources = sample.records
        .map((r) => healthSourceLabel(l, sourceForHealthMetric(r)))
        .toSet()
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTappable(
          onPress: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthDateLabel(l, sample.day),
                        style: context.rowTitleStyle,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(sources, style: context.captionStyle),
                    ],
                  ),
                ),
                Flexible(
                  child: Text(
                    kind.formatValue(l, sample.value),
                    style: context.labelStyle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.xs,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in sample.records) _RecordEvidence(row: row),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecordEvidence extends StatelessWidget {
  const _RecordEvidence({required this.row});
  final HealthMetric row;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final manual = sourceForHealthMetric(row) == HealthMetricSource.manual;
    final timestamp = row.kind.isMeasurement && manual
        ? healthDateLabel(l, healthMetricDay(row))
        : DateFormat.MMMd(l.localeName)
              .add_Hm()
              .format(row.capturedAt.toLocal());
    Map<String, Object?> payload = const {};
    try {
      final decoded = jsonDecode(row.payloadJson ?? '{}');
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on Object {
      /* Records remain readable if optional metadata is malformed. */
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$timestamp · ${row.kind.formatValue(l, healthDisplayValue(row))}',
            style: context.captionStyle,
          ),
          if (payload['note'] case final String note when note.isNotEmpty)
            Text(note, style: context.captionStyle),
          if (row.kind == HealthMetricKind.sleepSession)
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s4,
              children: [
                for (final (key, label) in [
                  ('deep', l.healthSleepDeepLabel),
                  ('rem', l.healthSleepRemLabel),
                  ('light', l.healthSleepLightLabel),
                  ('awake', l.healthSleepAwakeLabel),
                ])
                  if (payload[key] case final num seconds
                      when seconds.isFinite && seconds >= 0)
                    Text(
                      '$label · ${HealthMetricKind.sleepSession.formatValue(l, seconds / 3600)}',
                      style: context.microCaptionStyle,
                    ),
              ],
            ),
          if (manual && row.kind.isMeasurement)
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.pencil, size: AppIconSizes.xs),
              onPress: () => showBodyMeasurementEntrySheet(
                context: context,
                initialKind: row.kind,
                initialMetric: row,
              ),
              child: Text(l.healthEditMeasurement),
            ),
        ],
      ),
    );
  }
}

String healthSourceLabel(AppLocalizations l, HealthMetricSource source) =>
    switch (source) {
      HealthMetricSource.manual => l.healthManualSource,
      HealthMetricSource.unknown => l.healthUnknownSource,
      _ => source.label,
    };
