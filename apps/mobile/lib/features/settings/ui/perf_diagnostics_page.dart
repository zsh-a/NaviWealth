import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/perf/frame_timing_collector.dart';
import '../../../core/perf/providers.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

final _perfDiagnosticsTickerProvider = StreamProvider.autoDispose<int>((ref) {
  return Stream.periodic(const Duration(seconds: 1), (tick) => tick);
});

class PerfDiagnosticsPage extends ConsumerWidget {
  const PerfDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(_perfDiagnosticsTickerProvider);
    final stats = ref.watch(frameTimingCollectorProvider).statsForAll();

    return AppPageScaffold(
      title: l10n.settingsPerfTitle,
      childPad: false,
      child: SettingsPageFrame(
        maxWidth: AdaptiveMaxWidth.page,
        children: [
          ResponsiveTwoColumn(
            left: _SummaryCard(stats: stats),
            right: _TimingCard(stats: stats),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats});

  final FrameStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsPerfRecentFrames, style: context.bodyCaptionStyle),
          const SizedBox(height: AppSpacing.s8),
          Text(
            stats.frameCount.toString(),
            style: TypographyTokens.numericDisplay.copyWith(
              color: context.theme.colors.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _MetricRow(
            label: l10n.settingsPerfJankFrames,
            value: '${stats.jankFrameCount} / ${_percent(stats.jankRatio)}',
          ),
          _MetricRow(
            label: l10n.settingsPerfFrameBudget,
            value: _ms(stats.frameBudgetUs),
          ),
        ],
      ),
    );
  }
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({required this.stats});

  final FrameStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsPerfTimingTitle, style: context.bodyCaptionStyle),
          const SizedBox(height: AppSpacing.s8),
          _MetricRow(
            label: l10n.settingsPerfTotalP50,
            value: _ms(stats.p50TotalUs),
          ),
          _MetricRow(
            label: l10n.settingsPerfTotalP95,
            value: _ms(stats.p95TotalUs),
          ),
          const SizedBox(height: AppSpacing.s8),
          _MetricRow(
            label: l10n.settingsPerfBuildP95,
            value: _ms(stats.p95BuildUs),
          ),
          _MetricRow(
            label: l10n.settingsPerfRasterP95,
            value: _ms(stats.p95RasterUs),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.foreground,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Text(
            value,
            style: TypographyTokens.numericCaption.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

String _ms(int microseconds) {
  return '${(microseconds / 1000).toStringAsFixed(1)} ms';
}

String _percent(double ratio) {
  return '${(ratio * 100).toStringAsFixed(1)}%';
}
