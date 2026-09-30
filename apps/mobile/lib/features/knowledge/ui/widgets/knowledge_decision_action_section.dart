import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/lifeos/ui/source_action_control.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/shell/settings_route_paths.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_models.dart';

const String _knowledgeDecisionRowFamily = 'know:knowledge_decisions';

class KnowledgeDecisionActionSection extends ConsumerWidget {
  const KnowledgeDecisionActionSection({
    super.key,
    required this.decision,
    this.onBusyChanged,
  });

  final KnowledgeDecision decision;
  final ValueChanged<bool>? onBusyChanged;

  LifeActionSource get _source =>
      (rowFamily: _knowledgeDecisionRowFamily, rowId: decision.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(lifeOpenActionCountProvider);
    if (availability.isLoading) {
      return _section(context, children: const [kDefaultLoading]);
    }
    if (availability.hasError) {
      return _failure(
        context,
        () => ref.invalidate(lifeOpenActionCountProvider),
      );
    }
    if (availability.asData?.value == null) {
      final l10n = AppLocalizations.of(context);
      return _section(
        context,
        children: [
          Text(
            l10n.knowledgeDecisionActionUnavailable,
            style: context.bodyCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          SizedBox(
            width: double.infinity,
            child: AppQuietButton(
              label: l10n.agentSettingsManageDomains,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.push(SettingsRoutes.domains),
            ),
          ),
        ],
      );
    }

    final l10n = AppLocalizations.of(context);
    return _section(
      context,
      children: [
        Text(
          l10n.knowledgeDecisionActionDescription,
          style: context.bodyCaptionStyle,
        ),
        SourceActionControl(
          source: _source,
          onBusyChanged: onBusyChanged,
          createKey: const Key('knowledge-decision-create-action'),
          openKey: const Key('knowledge-decision-open-action'),
          createLabel: l10n.knowledgeDecisionCreateAction,
          openLabel: l10n.knowledgeDecisionOpenAction,
          confirmTitle: l10n.knowledgeDecisionActionConfirmTitle,
          confirmBody: l10n.knowledgeDecisionActionConfirmBody,
          successMessage: l10n.knowledgeDecisionActionCreated,
          buildDraft: (replacesActionId) {
            final expected = decision.expectedOutcome?.trim();
            final note = StringBuffer(decision.question);
            if (expected != null && expected.isNotEmpty) {
              note
                ..writeln()
                ..write(l10n.knowledgeDecisionActionExpectedOutcome(expected));
            }
            return LifeActionDraft(
              title: decision.selectedLabel.trim().isEmpty
                  ? decision.question
                  : decision.selectedLabel,
              note: note.toString(),
              sourceDomain: 'knowledge',
              sourceRowFamily: _source.rowFamily,
              sourceRowId: _source.rowId,
              sourceLabelSnapshot: decision.question,
              replacesActionId: replacesActionId,
            );
          },
          onCreated: (_) => recordProductMetric(
            () => ref.read(productMetricsProvider.notifier),
            ProductFunnelEvent.knowledgeDecisionActionCreated,
            success: true,
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, {required List<Widget> children}) {
    return AppSection.item(
      title: AppLocalizations.of(context).knowledgeDecisionActionTitle,
      children: children,
    );
  }

  Widget _failure(BuildContext context, VoidCallback retry) => _section(
    context,
    children: [
      AppEmptyState.error(
        title: AppLocalizations.of(context).commonLoadFailed,
        retryLabel: AppLocalizations.of(context).commonRetry,
        onRetry: retry,
      ),
    ],
  );
}
