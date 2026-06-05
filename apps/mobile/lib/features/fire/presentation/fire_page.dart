import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/fire_providers.dart';
import '../domain/fire_projection.dart';
import 'fire_dashboard_content.dart';

class FirePage extends ConsumerWidget {
  const FirePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(fireDashboardViewProvider);
    return AppPageScaffold(
      title: l10n.fireAppBarTitle,
      childPad: false,
      child: PageSkeletonShell<FireDashboardView>(
        skeleton: const FireSkeleton(),
        isLoading: viewAsync.isLoading,
        child: viewAsync.when(
          loading: () => const FireSkeleton(),
          error: (e, _) => _ErrorState(
            message: l10n.fireLoadError('$e'),
            onRetry: () => ref.invalidate(fireDashboardViewProvider),
          ),
          data: (view) => view.goal.isConfigured
              ? FireConfiguredBody(view: view)
              : const FireUnconfiguredBody(),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        children: [
          Icon(
            FLucideIcons.circleAlert,
            color: context.theme.colors.destructive,
            size: AppIconSizes.xl,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: Text(l10n.fireRetry),
          ),
        ],
      ),
    );
  }
}
