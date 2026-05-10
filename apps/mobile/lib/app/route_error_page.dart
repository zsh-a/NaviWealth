import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

/// Rendered by [GoRouter.errorBuilder] when routing fails — typically because
/// no route matched the URL (404). Surface a "back to overview" button so
/// the user is never trapped on a dead-end page.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.state});

  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final error = state.error;
    final hasError = error != null;
    final title = hasError ? l10n.routeNotFoundTitle : l10n.routeErrorTitle;
    final message = hasError
        ? l10n.routeNotFoundMessage(state.uri.toString())
        : l10n.commonError;

    return FScaffold(
      childPad: false,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasError
                      ? Icons.travel_explore_outlined
                      : Icons.error_outline,
                  size: 56,
                  color: colors.destructive,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: typography.lg.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FButton(
                  variant: FButtonVariant.primary,
                  onPress: () => context.go(AppRoutes.home),
                  prefix: const Icon(Icons.home_outlined, size: 16),
                  child: Text(l10n.routeGoHome),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
