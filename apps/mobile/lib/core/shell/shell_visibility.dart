/// Shell-tab visibility for offstage [StatefulShellRoute.indexedStack]
/// branches.
///
/// Indexed-stack tabs stay mounted when inactive. Without a pause signal,
/// their Riverpod watches keep Drift streams and chart rebuilds alive in the
/// background. [DomainTabsShell] publishes the active tab root path here;
/// tab pages gate live work with [shellTabIsActiveProvider] / [ShellTabPause].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Route path of the currently visible domain-tab root (e.g. `/activity`).
///
/// Empty string means "unknown / not under a domain shell" — treat as active
/// so standalone routes and tests keep working without shell plumbing.
final activeShellTabPathProvider = Provider<String>((ref) => '');

/// Whether [routePath] is the active shell tab (or a nested route under it).
final shellTabIsActiveProvider = Provider.family<bool, String>((
  ref,
  routePath,
) {
  final active = ref.watch(activeShellTabPathProvider);
  return isShellTabPathActive(activeTabPath: active, routePath: routePath);
});

/// Pure helper for tests and non-Riverpod call sites.
bool isShellTabPathActive({
  required String activeTabPath,
  required String routePath,
}) {
  if (activeTabPath.isEmpty) return true;
  if (routePath.isEmpty) return true;
  return routePath == activeTabPath || routePath.startsWith('$activeTabPath/');
}

/// Unmounts [child] while its shell tab is offstage so Riverpod watches and
/// animations stop. When the tab becomes active again, [child] remounts.
///
/// Local [State] above this widget (page-level controllers) is preserved by
/// the outer indexed stack; only the gated subtree tears down.
class ShellTabPause extends ConsumerWidget {
  const ShellTabPause({
    super.key,
    required this.routePath,
    required this.child,
    this.placeholder = const SizedBox.expand(),
  });

  /// Tab root path this surface belongs to (e.g. [FinanceRoutes.home]).
  final String routePath;

  /// Live tree — only mounted while the tab is active.
  final Widget child;

  /// Shown while offstage. Keep this cheap (no providers / charts).
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(shellTabIsActiveProvider(routePath));
    if (!active) {
      return TickerMode(enabled: false, child: placeholder);
    }
    return child;
  }
}
