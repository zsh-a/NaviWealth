/// §5.10.5 — first-launch privacy onboarding.
///
/// Mounted by the app composition root so the sheet fires once after a
/// fresh install, before the user has a chance to ask AI for anything
/// cloud-bound. Writes a `shared_preferences` flag on dismissal so
/// re-opens never re-trigger it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/shell/settings_route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Scheduling guard so concurrent rebuilds don't queue multiple sheets.
bool _onboardingInFlight = false;

/// Mount on whichever surface should "guard" the first launch (the
/// home page is the canonical pick — it's the first thing the user
/// lands on after sign-in). Renders nothing.
class AiPrivacyOnboardingMount extends ConsumerStatefulWidget {
  const AiPrivacyOnboardingMount({super.key});

  @override
  ConsumerState<AiPrivacyOnboardingMount> createState() =>
      _AiPrivacyOnboardingMountState();
}

class _AiPrivacyOnboardingMountState
    extends ConsumerState<AiPrivacyOnboardingMount> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(aiPrivacyOnboardingSeenProvider);
    if (!seen && !_scheduled && !_onboardingInFlight) {
      _scheduled = true;
      _onboardingInFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _onboardingInFlight = false;
          return;
        }
        showAiPrivacyOnboardingSheet(context).whenComplete(() async {
          _onboardingInFlight = false;
          await markAiPrivacyOnboardingSeen(
            ref.read(sharedPreferencesProvider),
          );
        });
      });
    }
    return const SizedBox.shrink();
  }
}

@visibleForTesting
void resetAiPrivacyOnboardingForTest() {
  _onboardingInFlight = false;
}

Future<void> showAiPrivacyOnboardingSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.aiPrivacyOnboardingTitle,
    maxHeightFactor: 0.9,
    builder: (_) => const _AiPrivacyOnboardingSheet(),
  );
}

class _AiPrivacyOnboardingSheet extends ConsumerWidget {
  const _AiPrivacyOnboardingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(aiPrivacySettingsProvider);
    final controller = ref.read(aiPrivacySettingsProvider.notifier);
    final colors = context.theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FLucideIcons.lock,
              size: AppIconSizes.md,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.aiPrivacyOnboardingBody,
                style: context.bodyCaptionStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        _OnboardingChoiceTile(
          mode: AiPrivacyMode.amountsAllowed,
          selected: settings.mode,
          label: l10n.aiPrivacyModeAmountsAllowedLabel,
          description: l10n.aiPrivacyModeAmountsAllowedDescription,
          onSelect: controller.setMode,
        ),
        const SizedBox(height: AppSpacing.s8),
        _OnboardingChoiceTile(
          mode: AiPrivacyMode.amountsBucketed,
          selected: settings.mode,
          label: l10n.aiPrivacyModeAmountsBucketedLabel,
          description: l10n.aiPrivacyModeAmountsBucketedDescription,
          onSelect: controller.setMode,
        ),
        const SizedBox(height: AppSpacing.s8),
        _OnboardingChoiceTile(
          mode: AiPrivacyMode.amountsLocal,
          selected: settings.mode,
          label: l10n.aiPrivacyModeAmountsLocalLabel,
          description: l10n.aiPrivacyModeAmountsLocalDescription,
          onSelect: controller.setMode,
        ),
        const SizedBox(height: AppSpacing.s20),
        LayoutBuilder(
          builder: (context, constraints) {
            final settingsButton = FButton(
              onPress: () {
                Navigator.of(context).pop();
                context.goNamed(SettingsRouteNames.aiPrivacy);
              },
              variant: FButtonVariant.outline,
              child: Text(l10n.aiPrivacyTitle),
            );
            final confirmButton = FButton(
              onPress: () => Navigator.of(context).pop(),
              child: Text(l10n.aiPrivacyOnboardingConfirm),
            );
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  settingsButton,
                  const SizedBox(height: AppSpacing.s8),
                  confirmButton,
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: settingsButton),
                const SizedBox(width: AppSpacing.s12),
                Expanded(child: confirmButton),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OnboardingChoiceTile extends StatelessWidget {
  const _OnboardingChoiceTile({
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
    final isSelected = mode == selected;
    return SoftCard(
      onPress: () => onSelect(mode),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FRadio(
            value: isSelected,
            onChange: (_) => onSelect(mode),
            semanticsLabel: label,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(description, style: context.captionStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
