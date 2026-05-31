/// §5.10.5 — AI privacy posture settings.
///
/// Three radio choices for the cloud-egress mode plus one toggle for
/// account-name masking. Reads + writes [aiPrivacySettingsProvider];
/// the router consumes the resulting [AiPrivacySettings.maxBudgetTier]
/// at request time and the command-palette status badge mirrors the
/// current mode label.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AiPrivacyPage extends ConsumerWidget {
  const AiPrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(aiPrivacySettingsProvider);
    final controller = ref.read(aiPrivacySettingsProvider.notifier);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.aiPrivacyTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, AppSpacing.s24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(
              l10n.aiPrivacyIntro,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ModeRow(
                  mode: AiPrivacyMode.amountsAllowed,
                  selected: settings.mode,
                  label: l10n.aiPrivacyModeAmountsAllowedLabel,
                  description: l10n.aiPrivacyModeAmountsAllowedDescription,
                  onSelect: controller.setMode,
                ),
                const FDivider(),
                _ModeRow(
                  mode: AiPrivacyMode.amountsBucketed,
                  selected: settings.mode,
                  label: l10n.aiPrivacyModeAmountsBucketedLabel,
                  description: l10n.aiPrivacyModeAmountsBucketedDescription,
                  onSelect: controller.setMode,
                ),
                const FDivider(),
                _ModeRow(
                  mode: AiPrivacyMode.amountsLocal,
                  selected: settings.mode,
                  label: l10n.aiPrivacyModeAmountsLocalLabel,
                  description: l10n.aiPrivacyModeAmountsLocalDescription,
                  onSelect: controller.setMode,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.aiPrivacyMaskAccountsLabel,
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        l10n.aiPrivacyMaskAccountsDescription,
                        style: context.theme.typography.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FSwitch(
                  value: settings.maskAccountNames,
                  onChange: controller.setMaskAccountNames,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.label,
    required this.description,
    required this.onSelect,
  });

  final AiPrivacyMode mode;
  final AiPrivacyMode selected;
  final String label;
  final String description;
  final void Function(AiPrivacyMode mode) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isSelected = mode == selected;
    return FTappable(
      onPress: () => onSelect(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FRadio(
              value: isSelected,
              onChange: (_) => onSelect(mode),
              semanticsLabel: label,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.theme.typography.sm.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    description,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
