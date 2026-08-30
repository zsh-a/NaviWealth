import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/fire_providers.dart';
import '../domain/fire_projection.dart';
import 'fire_dashboard_content.dart';
import 'fire_goal_form.dart';

class FirePage extends ConsumerWidget {
  const FirePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(fireDashboardViewProvider);
    final configured = viewAsync.value?.goal.isConfigured == true;
    return AppPageScaffold(
      title: l10n.fireAppBarTitle,
      childPad: false,
      actions: [
        if (configured)
          AppHeaderAction(
            semanticsLabel: l10n.fireEditGoal,
            icon: const Icon(FLucideIcons.pencil, size: AppIconSizes.md),
            onPress: () => showFireGoalSheet(context),
          ),
      ],
      child: PageSkeletonShell<FireDashboardView>(
        skeleton: const FireSkeleton(),
        isLoading: viewAsync.isLoading,
        child: viewAsync.when(
          loading: () => const FireSkeleton(),
          error: (e, st) => kDefaultError(
            context,
            e,
            st,
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
