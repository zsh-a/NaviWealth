import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../format/formatters.dart';
import '../agent_artifact.dart';
import '../providers.dart';
import 'agent_result_card.dart';

/// The one agent-results surface every domain mounts (blueprint §8.5).
///
/// Domains previously hand-rolled four different state grammars around
/// [AgentResultsSection] — skeleton card vs `SizedBox.shrink()` loading,
/// three empty-state dialects, and four "last run" meta formats. This panel
/// legislates them:
///
/// * loading (no cached value) → quiet placeholder card;
/// * error (no cached value)   → state card + retry;
/// * empty                     → state card with an optional generate CTA;
/// * data                      → [AgentResultsSection] with the meta label
///   fixed to [AppFormatters.relativeTime].
///
/// `showPlaceholderStates: false` keeps signal-first surfaces (Reviews)
/// quiet during loading/empty instead of stacking status shells.
class AgentResultsPanel extends ConsumerWidget {
  const AgentResultsPanel({
    super.key,
    required this.resultsAsync,
    required this.onReload,
    required this.onOpen,
    required this.onRunAgain,
    this.onGenerate,
    this.generating = false,
    this.showPlaceholderStates = true,
    this.bottomGap = AppSpacing.s16,
  });

  final AsyncValue<AgentResultBundle?> resultsAsync;

  /// Invalidate/refresh the backing provider after a failure.
  final VoidCallback onReload;

  final void Function(AgentArtifact artifact) onOpen;

  /// Re-run the agent behind a stale entry.
  final Future<void> Function(String agentId) onRunAgain;

  /// Empty-state CTA — run the agent for the first time. When null the
  /// empty state renders without a button.
  final VoidCallback? onGenerate;

  /// Disables [onGenerate] and shows a busy spinner on the CTA.
  final bool generating;

  final bool showPlaceholderStates;

  /// Trailing gap below the panel (page rhythm slot).
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (resultsAsync.isLoading && !resultsAsync.hasValue) {
      if (!showPlaceholderStates) return const SizedBox.shrink();
      return _frame(
        AgentResultPanelStateCard(
          icon: FLucideIcons.loaderCircle,
          title: l10n.agentResultsLoadingTitle,
          message: l10n.agentResultsLoadingBody,
          loading: true,
        ),
      );
    }
    if (resultsAsync.hasError && !resultsAsync.hasValue) {
      return _frame(
        AgentResultPanelStateCard(
          icon: FLucideIcons.triangleAlert,
          title: l10n.agentResultsErrorTitle,
          message: userSafeErrorMessage(context, resultsAsync.error!),
          error: true,
          onRetry: onReload,
        ),
      );
    }

    final bundle = resultsAsync.value;
    if (bundle == null || bundle.visibleEntries.isEmpty) {
      final generate = onGenerate;
      if (generate == null && !showPlaceholderStates) {
        return const SizedBox.shrink();
      }
      return _frame(
        AgentEmptyStateCard(onGenerate: generate, generating: generating),
      );
    }

    return _frame(
      AgentResultsSection(
        bundle: bundle,
        metaLabelBuilder: (at) => agentResultMetaLabel(l10n, at),
        onOpen: onOpen,
        onRetry: onRunAgain,
      ),
    );
  }

  Widget _frame(Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      child,
      if (bottomGap > 0) SizedBox(height: bottomGap),
    ],
  );
}

/// The legislated agent empty state (blueprint §8.5): compact CTA row, not
/// a large empty shell. Shared by the bundle panel and Health's briefing.
class AgentEmptyStateCard extends StatelessWidget {
  const AgentEmptyStateCard({
    super.key,
    this.onGenerate,
    this.generating = false,
  });

  final VoidCallback? onGenerate;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final generate = onGenerate;
    return SoftCard.flat(
      padding: AppPageRhythm.densePadding,
      child: Row(
        children: [
          AppIconTile(
            icon: FLucideIcons.sparkles,
            color: context.theme.colors.primary,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.agentResultsEmptyTitle, style: context.rowTitleStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(l10n.agentResultsEmptyBody, style: context.captionStyle),
              ],
            ),
          ),
          if (generate != null) ...[
            const SizedBox(width: AppSpacing.s12),
            FButton(
              onPress: generating ? null : generate,
              child: generating
                  ? const FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
                    )
                  : Text(l10n.agentResultsGenerateAction),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one "last run" meta format for agent results across every domain
/// (blueprint §8.5): relative time with a date fallback after a week.
String agentResultMetaLabel(AppLocalizations l10n, DateTime at) {
  final when = at.toLocal();
  return AppFormatters.relativeTime(
    when,
    justNow: l10n.aiChatRelativeJustNow,
    minutesAgo: l10n.aiChatRelativeMinutesAgo,
    hoursAgo: l10n.aiChatRelativeHoursAgo,
    daysAgo: l10n.aiChatRelativeDaysAgo,
    dateFallback: (d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}',
  );
}
