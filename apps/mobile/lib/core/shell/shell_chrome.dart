/// Cross-domain shell chrome primitives.
///
/// Domain tab pages use this file for the stable shell-facing API:
/// [ShellTabScaffold], [ShellActionRow], and the tab padding helpers. The
/// app layer injects concrete global chrome such as the domain switcher,
/// command palette, and Settings navigation through [shellChromeBuildersProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Width at or above which the persistent left dock + sidebar own the
/// global chrome, so the header/greeting don't repeat it.
const double kTabBarOffset = 80;
const double _desktopChromeBreakpoint = Breakpoints.shellDesktop;

bool _showInlineChrome(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _desktopChromeBreakpoint;

typedef ShellChromeLeadingBuilder =
    Widget? Function(BuildContext context, WidgetRef ref);

typedef ShellChromeHeaderActionsBuilder =
    List<ShellHeaderActionSpec> Function(BuildContext context, WidgetRef ref);

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

  List<ShellHeaderActionSpec> buildHeaderActions(
    BuildContext context,
    WidgetRef ref,
  ) =>
      headerActionsBuilder?.call(context, ref) ??
      const <ShellHeaderActionSpec>[];

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

/// Semantic description of a shell header action.
///
/// Domain and app-global actions share this type so [ShellTabScaffold] can
/// apply one ordering and compact-width budget instead of letting every page
/// grow an independent icon row. Lower [order] values are shown first.
class ShellHeaderActionSpec {
  const ShellHeaderActionSpec({
    required this.icon,
    required this.label,
    required this.onPress,
    this.order = 0,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final int order;
  final int badgeCount;
}

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
    this.actions = const <ShellHeaderActionSpec>[],
    this.childPad = false,
    this.collapseOnScroll = true,
  });

  /// Header title, e.g. `l10n.navActivity` or `'今日 · HealthOS'`.
  final String title;

  /// Page body — owns its own scroll + padding.
  final Widget child;

  /// Domain-owned trailing header actions (`+`, filter, …). The injected
  /// global actions are appended automatically.
  final List<ShellHeaderActionSpec> actions;

  /// Forwarded to [DomainTabScaffold.childPad].
  final bool childPad;

  /// Forwarded to [DomainTabScaffold.collapseOnScroll].
  final bool collapseOnScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inline = _showInlineChrome(context);
    final chrome = ref.watch(shellChromeBuildersProvider);
    final mergedActions = <ShellHeaderActionSpec>[
      ...actions,
      if (inline) ...chrome.buildHeaderActions(context, ref),
    ]..sort((a, b) => a.order.compareTo(b.order));
    final directActionBudget = inline ? 2 : mergedActions.length;
    final directActions = mergedActions
        .take(directActionBudget)
        .toList(growable: false);
    final overflowActions = mergedActions
        .skip(directActionBudget)
        .toList(growable: false);
    return DomainTabScaffold(
      title: title,
      childPad: childPad,
      collapseOnScroll: collapseOnScroll,
      leading: inline ? chrome.buildLeading(context, ref) : null,
      actions: <Widget>[
        for (final action in directActions)
          FHeaderAction(
            icon: _ShellHeaderActionIcon(
              icon: action.icon,
              badgeCount: action.badgeCount,
            ),
            semanticsLabel: action.badgeCount > 0
                ? '${action.label} (${action.badgeCount})'
                : action.label,
            onPress: action.onPress,
          ),
        if (overflowActions.isNotEmpty)
          FHeaderAction(
            icon: const Icon(FLucideIcons.ellipsis),
            semanticsLabel: AppLocalizations.of(context).shellMoreActions,
            onPress: () => _showHeaderActionOverflow(context, overflowActions),
          ),
      ],
      child: child,
    );
  }
}

class _ShellHeaderActionIcon extends StatelessWidget {
  const _ShellHeaderActionIcon({required this.icon, required this.badgeCount});

  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    if (badgeCount <= 0) return Icon(icon);
    final label = badgeCount > 9 ? '9+' : '$badgeCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        PositionedDirectional(
          top: -AppSpacing.s6,
          end: -AppSpacing.s8,
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.theme.colors.primary,
                shape: BoxShape.circle,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.s16,
                  minHeight: AppSpacing.s16,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                    ),
                    child: Text(
                      label,
                      style: context.microLabelStyle.copyWith(
                        color: context.theme.colors.primaryForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _showHeaderActionOverflow(
  BuildContext context,
  List<ShellHeaderActionSpec> actions,
) async {
  final l10n = AppLocalizations.of(context);
  final selected = await showAppSheet<ShellHeaderActionSpec>(
    context: context,
    title: l10n.shellMoreActions,
    builder: (sheetContext) => AppActionSheetList(
      children: <AppActionSheetTile>[
        for (final action in actions)
          AppActionSheetTile(
            icon: action.icon,
            title: action.label,
            subtitle: '',
            onPress: () => Navigator.of(sheetContext).pop(action),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  selected.onPress();
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

/// Headerless top-level tab scaffold that still belongs to the app shell.
///
/// Most domain tab roots should use [ShellTabScaffold]. A small number of
/// cockpit-style roots, currently Finance Today, intentionally own their
/// in-content hero/header instead of rendering an `FHeader`. Those pages still
/// need to be shell-owned so global chrome, cross-platform back behavior, and
/// tab padding stay centralized. Use [ShellActionRow] inside the page's hero
/// row to render the injected domain switcher + global actions on compact
/// viewports.
class ShellCanvasScaffold extends StatelessWidget {
  const ShellCanvasScaffold({
    super.key,
    required this.child,
    this.childPad = false,
    this.transparentMaterial = true,
    this.resizeToAvoidBottomInset,
  });

  final Widget child;
  final bool childPad;
  final bool transparentMaterial;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return AppCanvasScaffold(
      childPad: childPad,
      transparentMaterial: transparentMaterial,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      child: child,
    );
  }
}
