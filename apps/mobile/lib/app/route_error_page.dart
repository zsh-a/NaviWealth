import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

/// Rendered by [GoRouter.errorBuilder] when routing fails — typically because
/// no route matched the URL (404). `state.error` is `GoException?`; when it's
/// non-null we show the URL the user tried, when it's null (uncommon) we fall
/// back to a generic error string. Either way we surface a "back to overview"
/// button so the user is never trapped on a dead-end page.
///
/// Note: exceptions thrown from inside a route's `builder` do NOT flow here —
/// those are caught by Flutter's `ErrorWidget.builder`. If you need to render
/// a friendly screen for builder-time crashes, install your own
/// `ErrorWidget.builder` at app start.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.state});

  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final error = state.error;
    final hasError = error != null;
    final title = hasError ? l10n.routeNotFoundTitle : l10n.routeErrorTitle;
    final message = hasError
        ? l10n.routeNotFoundMessage(state.uri.toString())
        : l10n.commonError;

    return Scaffold(
      body: SafeArea(
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
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                AppButton.primary(
                  label: l10n.routeGoHome,
                  icon: Icons.home_outlined,
                  onPressed: () => context.go(AppRoutes.home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
