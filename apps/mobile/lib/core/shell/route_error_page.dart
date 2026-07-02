import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Rendered by [GoRouter.errorBuilder] when routing fails — typically because
/// no route matched the URL (404). Surface a "back to overview" button so
/// the user is never trapped on a dead-end page.
class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.state, this.homePath = '/'});

  final GoRouterState state;
  final String homePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final error = state.error;
    final hasError = error != null;
    final title = hasError ? l10n.routeNotFoundTitle : l10n.routeErrorTitle;
    final message = hasError
        ? l10n.routeNotFoundMessage(state.uri.toString())
        : l10n.commonError;
    final canPop = GoRouter.of(context).canPop();

    return FScaffold(
      childPad: false,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasError ? FLucideIcons.globe : FLucideIcons.circleAlert,
                  size: 56,
                  color: colors.destructive,
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  title,
                  style: context.titleLabelStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  message,
                  style: context.bodyCaptionStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canPop) ...[
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: () => smartPop(context),
                        prefix: const Icon(
                          FLucideIcons.arrowLeft,
                          size: AppIconSizes.xs,
                        ),
                        child: Text(l10n.routeGoBack),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                    ],
                    FButton(
                      variant: FButtonVariant.primary,
                      onPress: () => context.go(homePath),
                      prefix: const Icon(
                        FLucideIcons.home,
                        size: AppIconSizes.sm,
                      ),
                      child: Text(l10n.routeGoHome),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
