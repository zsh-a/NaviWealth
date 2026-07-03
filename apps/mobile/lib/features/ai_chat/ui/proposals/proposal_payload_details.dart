import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

class ProposalPayloadDetails extends ConsumerWidget {
  const ProposalPayloadDetails({super.key, required this.plan, this.overrides});

  final ReadyProposalPlan plan;
  final Map<String, Object?>? overrides;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final rows =
        registry.metaFor(plan.kind)?.previewRows?.call(l10n, plan, overrides) ??
        const <ProposalKindRow>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.background.withValues(
          alpha: AppOpacity.prominent,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: context.theme.colors.border.withValues(
            alpha: AppOpacity.disabled,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: AppControlWidths.aiCompactColumn,
                    child: Text(row.label, style: context.microCaptionStyle),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      row.value,
                      style: context.captionStyle.copyWith(
                        color: context.theme.colors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
