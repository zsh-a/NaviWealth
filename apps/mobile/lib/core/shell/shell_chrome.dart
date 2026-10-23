/// Cross-domain shell chrome primitives.
///
/// Domain tab pages use this file for the stable shell-facing API:
/// [ShellTabScaffold], [ShellPageHeading], and the tab padding helpers. The
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
const double _desktopChromeBreakpoint = Breakpoints.shellDesktop;

bool _showInlineChrome(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _desktopChromeBreakpoint;

typedef ShellChromeLeadingBuilder = Widget? Function(
  BuildContext context,
  WidgetRef ref,
);

typedef ShellChromeHeaderActionsBuilder = List<ShellHeaderActionSpec> Function(
  BuildContext context,
  WidgetRef ref,
);

typedef ShellChromeOpenAiAction = Future<void> Function(
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
    this.openAiAction,
  });

  static const empty = ShellChromeBuilders();

  final ShellChromeLeadingBuilder? leadingBuilder;
  final ShellChromeHeaderActionsBuilder? headerActionsBuilder;
  final ShellChromeOpenAiAction? openAiAction;

  Widget? buildLeading(BuildContext context, WidgetRef ref) =>
      leadingBuilder?.call(context, ref);

  List<ShellHeaderActionSpec> buildHeaderActions(
    BuildContext context,
    WidgetRef ref,
  ) =>
      headerActionsBuilder?.call(context, ref) ??
      const <ShellHeaderActionSpec>[];

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
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final int order;
  final int badgeCount;
  final Color? iconColor;
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
    this.directActionBudget = 2,
  }) : assert(directActionBudget >= 0);

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

  /// Number of actions kept directly in the header before the remainder is
  /// grouped under the adaptive overflow menu. Pages with a fixed primary
  /// action can reduce this to keep their chrome intentionally quiet.
  final int directActionBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inline = _showInlineChrome(context);
    final chrome = ref.watch(shellChromeBuildersProvider);
    return DomainTabScaffold(
      title: title,
      childPad: childPad,
      // Desktop keeps a stable, quiet title bar while independently
      // scrollable panes move below it. Touch layouts reclaim vertical space
      // with the existing direction-aware collapse behavior.
      collapseOnScroll: inline && collapseOnScroll,
      leading: inline ? chrome.buildLeading(context, ref) : null,
      actions: _headerActions(context, ref, actions, directActionBudget),
      child: child,
    );
  }
}

List<Widget> _headerActions(
  BuildContext context,
  WidgetRef ref,
  List<ShellHeaderActionSpec> actions,
  int directActionBudget,
) {
  final merged = <ShellHeaderActionSpec>[
    ...actions,
    if (_showInlineChrome(context))
      ...ref
          .watch(shellChromeBuildersProvider)
          .buildHeaderActions(context, ref),
  ]..sort((a, b) => a.order.compareTo(b.order));
  return [
    for (final action in merged.take(directActionBudget))
      AppHeaderAction(
        icon: _ShellHeaderActionIcon(
          icon: action.icon,
          color: action.iconColor,
          badgeCount: action.badgeCount,
        ),
        semanticsLabel: action.badgeCount > 0
            ? '${action.label} (${action.badgeCount})'
            : action.label,
        onPress: action.onPress,
      ),
    if (merged.length > directActionBudget)
      _ShellHeaderOverflow(actions: merged.skip(directActionBudget).toList()),
  ];
}

class _ShellHeaderActionIcon extends StatelessWidget {
  const _ShellHeaderActionIcon({
    required this.icon,
    required this.badgeCount,
    this.color,
  });

  final IconData icon;
  final int badgeCount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (badgeCount <= 0) return Icon(icon, color: color);
    final label = badgeCount > 9 ? '9+' : '$badgeCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color),
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

class _ShellHeaderOverflow extends StatelessWidget {
  const _ShellHeaderOverflow({required this.actions});

  final List<ShellHeaderActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).shellMoreActions;
    return AppAdaptiveActionMenu(
      title: label,
      actions: <AppAdaptiveAction>[
        for (final action in actions)
          AppAdaptiveAction(
            icon: action.icon,
            title: action.label,
            onPress: action.onPress,
          ),
      ],
      triggerBuilder: (context, openMenu, focusNode) => AppHeaderAction(
        semanticsLabel: label,
        icon: const Icon(FLucideIcons.ellipsis),
        focusNode: focusNode,
        onPress: openMenu,
      ),
    );
  }
}

/// Task heading for brief pages, with one shared action budget.
///
/// Domain actions and global actions use a single overflow menu. When the title
/// and controls cannot share a line, the controls wrap as a group instead of
/// squeezing the title into a narrow column. Desktop navigation owns the global
/// controls; domain actions remain available at every width.
class ShellPageHeading extends ConsumerWidget {
  const ShellPageHeading({
    super.key,
    required this.title,
    this.actions = const [],
    this.titleStyle,
    this.padding = const EdgeInsets.only(
      top: AppSpacing.s8,
      bottom: AppSpacing.s16,
    ),
  });

  final String title;
  final List<ShellHeaderActionSpec> actions;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leading = _showInlineChrome(context)
        ? ref.watch(shellChromeBuildersProvider).buildLeading(context, ref)
        : null;
    final controls = _headerActions(context, ref, actions, 1);
    return FHeaderData(
      actionStyle: context.theme.headerStyles.resolve({
        FHeaderVariant.nested,
        context.platformVariant,
      }).actionStyle,
      child: Padding(
        padding: padding,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: titleStyle ?? context.briefGreetingTitleStyle,
                ),
              ),
              if (leading != null || controls.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [?leading, ...controls],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Headerless top-level tab scaffold that still belongs to the app shell.
///
/// Most domain tab roots should use [ShellTabScaffold]. A small number of
/// cockpit-style roots — the Today briefs (Finance, Health, Execution) —
/// intentionally own their in-content hero/header instead of rendering an
/// `FHeader`. Those pages still
/// need to be shell-owned so global chrome, cross-platform back behavior, and
/// tab padding stay centralized. Use [ShellPageHeading] for the page's task
/// title, domain actions, and injected compact navigation.
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
