import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_controller.dart';

/// First-launch mode picker. Two cards — cloud account or local-only —
/// shown while [appModeProvider] is still `unset`. Picking either choice
/// persists the mode so the router never bounces back here on the next
/// cold start.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  _OnboardingChoice? _busyChoice;

  Future<void> _pickCloud() async {
    if (_busyChoice != null) return;
    setState(() => _busyChoice = _OnboardingChoice.cloud);
    try {
      await ref.read(authControllerProvider.notifier).chooseCloud();
      if (!mounted) return;
      context.go(AppRoutes.login);
    } finally {
      if (mounted) setState(() => _busyChoice = null);
    }
  }

  Future<void> _pickLocal() async {
    if (_busyChoice != null) return;
    setState(() => _busyChoice = _OnboardingChoice.local);
    try {
      await ref.read(authControllerProvider.notifier).enterLocalOnlyMode();
      // Route guard handles the redirect away from /onboarding once the
      // state flips to AuthLocalOnly.
    } finally {
      if (mounted) setState(() => _busyChoice = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s24,
                  vertical: AppSpacing.s32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SvgPicture.asset(
                      'assets/svg/logo.svg',
                      width: 72,
                      height: 72,
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    Text(
                      l10n.onboardingTitle,
                      style: context.theme.typography.lg,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      l10n.onboardingSubtitle,
                      style: context.theme.typography.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s32),
                    _ModeCard(
                      key: const ValueKey('onboarding.cloud'),
                      icon: FLucideIcons.cloud,
                      title: l10n.onboardingCloudTitle,
                      description: l10n.onboardingCloudDescription,
                      busy: _busyChoice == _OnboardingChoice.cloud,
                      onTap: _busyChoice == null ? _pickCloud : null,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _ModeCard(
                      key: const ValueKey('onboarding.local'),
                      icon: FLucideIcons.smartphone,
                      title: l10n.onboardingLocalOnlyTitle,
                      description: l10n.onboardingLocalOnlyDescription,
                      busy: _busyChoice == _OnboardingChoice.local,
                      onTap: _busyChoice == null ? _pickLocal : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _OnboardingChoice { cloud, local }

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      level: SoftCardLevel.raised,
      onPress: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: 18,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.medium),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primary, size: AppIconSizes.lg),
          ),
          const SizedBox(width: AppSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.theme.typography.md),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  description,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: AppIconSizes.h18,
              height: AppIconSizes.h18,
              child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
            )
          else
            Icon(
              FLucideIcons.chevronRight,
              color: colors.mutedForeground,
              size: AppIconSizes.md,
            ),
        ],
      ),
    );
  }
}
