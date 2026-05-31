/// §5.10.5 — first-launch privacy onboarding.
///
/// Mounted high in the widget tree (typically on the home page) so the
/// sheet fires once after a fresh install, before the user has a chance
/// to ask AI for anything cloud-bound. Writes a `shared_preferences`
/// flag on dismissal so re-opens never re-trigger it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
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
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (BuildContext sheetContext) =>
        const AppSheetSurface(child: _AiPrivacyOnboardingSheet()),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s20, AppSpacing.s16, AppSpacing.s20, AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.mutedForeground.withValues(alpha: AppOpacity.disabled),
                  borderRadius: BorderRadius.circular(AppRadius.xxs),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Row(
              children: <Widget>[
                Icon(FLucideIcons.lock, size: AppIconSizes.md, color: colors.primary),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    l10n.aiPrivacyOnboardingTitle,
                    style: context.theme.typography.lg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.aiPrivacyOnboardingBody,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: FButton(
                    onPress: () {
                      Navigator.of(context).pop();
                      context.goNamed(AppRouteNames.aiPrivacy);
                    },
                    variant: FButtonVariant.outline,
                    child: Text(l10n.aiPrivacyTitle),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: FButton(
                    onPress: () => Navigator.of(context).pop(),
                    child: Text(l10n.aiPrivacyOnboardingConfirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
    final colors = context.theme.colors;
    final isSelected = mode == selected;
    return SoftCard(
      onPress: () => onSelect(mode),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s12),
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
                Text(
                  label,
                  style: context.theme.typography.sm.copyWith(
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
    );
  }
}
