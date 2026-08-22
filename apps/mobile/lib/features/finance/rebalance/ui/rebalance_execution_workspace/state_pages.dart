part of '../rebalance_execution_workspace_page.dart';

class _WorkspaceStatePage extends StatelessWidget {
  const _WorkspaceStatePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(title: title, childPad: false, child: child);
  }
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: FLucideIcons.triangleAlert,
      title: message,
      action: AppActionButton(
        variant: FButtonVariant.outline,
        onPress: onRetry,
        child: Text(AppLocalizations.of(context).commonRetry),
      ),
    );
  }
}
