/// KnowledgeOS domain detail settings.
///
/// Shows KnowledgeOS-specific navigation. Reached from the Settings
/// overview's KnowledgeOS row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/settings_route_paths.dart';
import '../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_review_preferences.dart';
import '_widgets.dart';

class KnowledgeDomainSettingsPage extends ConsumerWidget {
  const KnowledgeDomainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final review = ref.watch(knowledgeReviewPreferencesProvider);

    return AppPageScaffold(
      title: 'KnowledgeOS',
      childPad: false,
      child: SettingsPageFrame(
        children: [
          KnowledgeSection(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            children: [
              InlineLinkRow(
                icon: FLucideIcons.brainCircuit,
                label: l10n.settingsDomainsKnowledgeMemoryTitle,
                subtitle: l10n.settingsDomainsKnowledgeMemorySubtitle,
                onTap: () => context.goNamed(SettingsRouteNames.aiModels),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.calendarClock,
                label: l10n.knowledgeSettingsReviewCadence,
                subtitle: l10n.knowledgeSettingsEveryDays(review.cadenceDays),
                onTap: () => _pickDays(
                  context,
                  title: l10n.knowledgeSettingsReviewCadence,
                  values: const <int>[1, 7, 14, 30],
                  selected: review.cadenceDays,
                  onSelected: ref
                      .read(knowledgeReviewPreferencesProvider.notifier)
                      .setCadenceDays,
                ),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.timerReset,
                label: l10n.knowledgeSettingsStaleThreshold,
                subtitle: l10n.knowledgeSettingsAfterDays(
                  review.staleAssumptionDays,
                ),
                onTap: () => _pickDays(
                  context,
                  title: l10n.knowledgeSettingsStaleThreshold,
                  values: const <int>[30, 60, 90, 180],
                  selected: review.staleAssumptionDays,
                  onSelected: ref
                      .read(knowledgeReviewPreferencesProvider.notifier)
                      .setStaleAssumptionDays,
                ),
              ),
              const AppGradientDivider(),
              InlineLinkRow(
                icon: FLucideIcons.bot,
                label: l10n.agentSettingsTitle,
                subtitle: l10n.agentSettingsSubtitle,
                onTap: () => context.goNamed(SettingsRouteNames.agents),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDays(
    BuildContext context, {
    required String title,
    required List<int> values,
    required int selected,
    required Future<void> Function(int value) onSelected,
  }) async {
    final value = await showAppSheet<int>(
      context: context,
      title: title,
      builder: (sheetContext) => Wrap(
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        children: [
          for (final days in values)
            FButton(
              variant: days == selected
                  ? FButtonVariant.primary
                  : FButtonVariant.outline,
              onPress: () => Navigator.of(sheetContext).pop(days),
              child: Text(
                AppLocalizations.of(
                  sheetContext,
                ).knowledgeSettingsEveryDays(days),
              ),
            ),
        ],
      ),
    );
    if (value != null) await onSelected(value);
  }
}
