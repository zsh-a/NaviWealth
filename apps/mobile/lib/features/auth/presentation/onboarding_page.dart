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
  bool _busy = false;

  Future<void> _pickCloud() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).chooseCloud();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  Future<void> _pickLocal() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).enterLocalOnlyMode();
    // Route guard handles the redirect away from /onboarding once the
    // state flips to AuthLocalOnly.
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
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SvgPicture.asset(
                      'assets/svg/logo.svg',
                      width: 72,
                      height: 72,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.onboardingTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.onboardingSubtitle,
                      style: context.theme.typography.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    _ModeCard(
                      key: const ValueKey('onboarding.cloud'),
                      icon: Icons.cloud_outlined,
                      title: l10n.onboardingCloudTitle,
                      description: l10n.onboardingCloudDescription,
                      onTap: _busy ? null : _pickCloud,
                    ),
                    const SizedBox(height: 12),
                    _ModeCard(
                      key: const ValueKey('onboarding.local'),
                      icon: Icons.smartphone_outlined,
                      title: l10n.onboardingLocalOnlyTitle,
                      description: l10n.onboardingLocalOnlyDescription,
                      onTap: _busy ? null : _pickLocal,
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      onPress: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.theme.typography.md),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: colors.mutedForeground,
            size: 20,
          ),
        ],
      ),
    );
  }
}
