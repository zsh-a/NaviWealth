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

import '../../../../core/ai/contracts/contracts.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

class AiPrivacyPage extends ConsumerWidget {
  const AiPrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(aiPrivacySettingsProvider);
    final controller = ref.read(aiPrivacySettingsProvider.notifier);
    return AppPageScaffold(
      title: l10n.aiPrivacyTitle,
      childPad: false,
      child: SettingsPageFrame(
        topPadding: AppSpacing.s8,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(l10n.aiPrivacyIntro, style: context.bodyCaptionStyle),
          ),
          const SizedBox(height: AppSpacing.s8),
          AppGroupedSurface(
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
                const AppGradientDivider(),
                _ModeRow(
                  mode: AiPrivacyMode.amountsBucketed,
                  selected: settings.mode,
                  label: l10n.aiPrivacyModeAmountsBucketedLabel,
                  description: l10n.aiPrivacyModeAmountsBucketedDescription,
                  onSelect: controller.setMode,
                ),
                const AppGradientDivider(),
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
          AppGroupedSurface(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: InlineSwitchRow(
              icon: FLucideIcons.eyeOff,
              label: l10n.aiPrivacyMaskAccountsLabel,
              subtitle: l10n.aiPrivacyMaskAccountsDescription,
              value: settings.maskAccountNames,
              onChanged: controller.setMaskAccountNames,
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FRadio(
              value: isSelected,
              onChange: (_) => onSelect(mode),
              semanticsLabel: label,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.labelStyle.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(description, style: context.captionStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
