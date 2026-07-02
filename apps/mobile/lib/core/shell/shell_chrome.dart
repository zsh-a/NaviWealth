/// Cross-domain shell chrome primitives.
///
/// Domain tab pages use this file for the stable shell-facing API:
/// [ShellTabScaffold], [ShellActionRow], and the tab padding helpers. The
/// app layer injects concrete global chrome such as the domain switcher,
/// command palette, and Settings navigation through [shellChromeBuildersProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/design_system.dart';

/// Width at or above which the persistent left dock + sidebar own the
/// global chrome, so the header/greeting don't repeat it.
const double kTabBarOffset = 80;
const double _desktopChromeBreakpoint = Breakpoints.desktop;

bool _showInlineChrome(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _desktopChromeBreakpoint;

typedef ShellChromeLeadingBuilder =
    Widget? Function(BuildContext context, WidgetRef ref);

typedef ShellChromeHeaderActionsBuilder =
    List<Widget> Function(BuildContext context, WidgetRef ref);

typedef ShellChromeActionRowBuilder =
    Widget? Function(BuildContext context, WidgetRef ref);

typedef ShellChromeOpenAiAction =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref, {
      String? prefill,
    });

/// App-provided chrome builders for top-level domain tab pages.
///
/// The default is intentionally empty so `core/shell` stays independent of
/// app routes and app-owned widgets. Production installs an override from the
/// app composition root.
class ShellChromeBuilders {
  const ShellChromeBuilders({
    this.leadingBuilder,
    this.headerActionsBuilder,
    this.actionRowBuilder,
    this.openAiAction,
  });

  static const empty = ShellChromeBuilders();

  final ShellChromeLeadingBuilder? leadingBuilder;
  final ShellChromeHeaderActionsBuilder? headerActionsBuilder;
  final ShellChromeActionRowBuilder? actionRowBuilder;
  final ShellChromeOpenAiAction? openAiAction;

  Widget? buildLeading(BuildContext context, WidgetRef ref) =>
      leadingBuilder?.call(context, ref);

  List<Widget> buildHeaderActions(BuildContext context, WidgetRef ref) =>
      headerActionsBuilder?.call(context, ref) ?? const <Widget>[];

  Widget? buildActionRow(BuildContext context, WidgetRef ref) =>
      actionRowBuilder?.call(context, ref);

  Future<void> openAi(BuildContext context, WidgetRef ref, {String? prefill}) {
    final action = openAiAction;
    if (action == null) return Future<void>.value();
    return action(context, ref, prefill: prefill);
  }
}

final shellChromeBuildersProvider = Provider<ShellChromeBuilders>(
  (ref) => ShellChromeBuilders.empty,
);

/// Page padding for top-level domain tabs.
///
/// On mobile, the domain tab shell publishes the floating bottom dock height
/// through `MediaQuery.padding.bottom`. Scroll views with explicit padding do
/// not consume that automatically, so tab pages should use this helper for
/// their root scroll/body padding.
EdgeInsets shellTabContentPadding(
  BuildContext context, {
  double left = AppSpacing.s16,
  double top = AppSpacing.s16,
  double right = AppSpacing.s16,
  double bottom = AppSpacing.s16,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    bottom + MediaQuery.paddingOf(context).bottom,
  );
}

/// Bottom offset for floating controls inside a top-level domain tab.
double shellTabFloatingActionBottom(
  BuildContext context, {
  double margin = AppSpacing.s16,
}) {
  return margin + MediaQuery.paddingOf(context).bottom;
}

/// Top-level tab / hub scaffold *with* the injected cross-domain chrome.
///
/// Wraps [DomainTabScaffold] and appends the app-provided leading widget and
/// global actions on compact viewports. Domains pass only their own concerns
/// (title, body, domain actions); the app chrome is injected consistently by
/// [shellChromeBuildersProvider].
class ShellTabScaffold extends ConsumerWidget {
  const ShellTabScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.childPad = false,
    this.collapseOnScroll = true,
  });

  /// Header title, e.g. `l10n.navActivity` or `'今日 · HealthOS'`.
  final String title;

  /// Page body — owns its own scroll + padding.
  final Widget child;

  /// Domain-owned trailing header actions (`+`, filter, …). The injected
  /// global actions are appended automatically.
  final List<Widget> actions;

  /// Forwarded to [DomainTabScaffold.childPad].
  final bool childPad;

  /// Forwarded to [DomainTabScaffold.collapseOnScroll].
  final bool collapseOnScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inline = _showInlineChrome(context);
    final chrome = ref.watch(shellChromeBuildersProvider);
    return DomainTabScaffold(
      title: title,
      childPad: childPad,
      collapseOnScroll: collapseOnScroll,
      leading: inline ? chrome.buildLeading(context, ref) : null,
      actions: [
        ...actions,
        if (inline) ...chrome.buildHeaderActions(context, ref),
      ],
      child: child,
    );
  }
}

/// In-content shell chrome slot for surfaces without an `FHeader`.
///
/// Currently used by the Today greeting header. Hidden on desktop where the
/// persistent dock / sidebar owns the global chrome.
class ShellActionRow extends ConsumerWidget {
  const ShellActionRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_showInlineChrome(context)) return const SizedBox.shrink();
    return ref
            .watch(shellChromeBuildersProvider)
            .buildActionRow(context, ref) ??
        const SizedBox.shrink();
  }
}
