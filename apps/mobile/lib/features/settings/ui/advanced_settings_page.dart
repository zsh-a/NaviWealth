import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_quality_report.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Low-frequency diagnostics kept out of the everyday settings hierarchy.
class AdvancedSettingsPage extends ConsumerWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final quality = ref.watch(agent_providers.agentQualityReportProvider);
    return AppPageScaffold(
      title: l10n.settingsAdvancedHubTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          quality.when(
            loading: () => const SkeletonCard(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: SkeletonBox(width: double.infinity, height: 88),
            ),
            error: (error, stackTrace) => kDefaultError(
              context,
              error,
              stackTrace,
              onRetry: () =>
                  ref.invalidate(agent_providers.agentQualityReportProvider),
            ),
            data: (report) => _AgentQualityDiagnostics(report: report),
          ),
          const SizedBox(height: AppSpacing.s16),
          AppSection.group(
            title: l10n.settingsAdvancedSection,
            children: [
              InlineLinkRow(
                icon: FLucideIcons.bug,
                label: l10n.settingsLogsTitle,
                subtitle: l10n.settingsLogsSubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.logs),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.activity,
                label: l10n.settingsPerfTitle,
                subtitle: l10n.settingsPerfSubtitle,
                onTap: () => context.pushNamed(SettingsRouteNames.performance),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentQualityDiagnostics extends StatelessWidget {
  const _AgentQualityDiagnostics({required this.report});

  final AgentQualityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final hasFailures = report.failedRuns > 0;
    return SoftCard.flat(
      padding: AppPageRhythm.densePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: FLucideIcons.chartNoAxesColumnIncreasing,
                color: hasFailures
                    ? context.appTheme.status.warning.fg
                    : colors.primary,
                size: AppSpacing.s32,
                iconSize: AppIconSizes.sm,
                backgroundOpacity: AppOpacity.subtle,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.agentQualityTitle, style: context.labelStyle),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      report.completedRuns == 0
                          ? l10n.agentQualityNoRuns
                          : l10n.agentQualityCompletedRuns(
                              report.completedRuns,
                            ),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s6,
            children: [
              if (report.completedRuns > 0) ...[
                _QualityFragment(
                  text: l10n.agentQualityReadyRate(
                    _percentage(report.highSignalRate),
                    report.readyRuns,
                    report.completedRuns,
                  ),
                  emphasis: report.readyRuns > 0,
                ),
                _QualityFragment(
                  text: l10n.agentQualityNoFindingRate(
                    _percentage(report.noFindingRate),
                    report.noFindingRuns,
                    report.completedRuns,
                  ),
                ),
                _QualityFragment(
                  text: l10n.agentQualityFailureRate(
                    _percentage(report.failureRate),
                    report.failedRuns,
                    report.completedRuns,
                  ),
                  danger: hasFailures,
                ),
              ],
              if (report.artifactCount > 0) ...[
                _QualityFragment(
                  text: l10n.agentQualitySuppressedRate(
                    _percentage(report.dismissedOrSnoozedRate),
                    report.dismissedOrSnoozedArtifacts,
                    report.artifactCount,
                  ),
                ),
                _QualityFragment(
                  text: l10n.agentQualityEvidenceRate(
                    _percentage(report.evidenceAnchorCoverageRate),
                    report.fullyAnchoredEvidenceArtifacts,
                    report.evidenceBearingArtifacts,
                  ),
                ),
              ],
              _QualityFragment(
                text: report.evidenceNavigationAttempts == 0
                    ? l10n.agentQualityEvidenceNavigationNoSamples
                    : l10n.agentQualityEvidenceNavigationRate(
                        _percentage(report.evidenceNavigationSuccessRate),
                        report.evidenceNavigationSuccesses,
                        report.evidenceNavigationAttempts,
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FLucideIcons.shieldCheck,
                size: AppIconSizes.xs,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  l10n.agentQualityPrivacyNote,
                  style: context.captionStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityFragment extends StatelessWidget {
  const _QualityFragment({
    required this.text,
    this.emphasis = false,
    this.danger = false,
  });

  final String text;
  final bool emphasis;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Text(
      text,
      style: context.captionStyle.copyWith(
        color: danger
            ? context.appTheme.status.danger.fg
            : emphasis
            ? colors.primary
            : colors.mutedForeground,
      ),
    );
  }
}

int _percentage(double value) => (value * 100).round().clamp(0, 100);
