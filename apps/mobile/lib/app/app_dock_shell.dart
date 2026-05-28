import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/shell/domain_shell.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/state/ai_context.dart';
import '../features/ai_chat/ui/ask_ai.dart';
import '../features/ingest/data/share_intent_service.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';

/// Outer multi-domain shell (`docs/lifeos-shell.md` §3 Option B, D-2.3b).
///
/// Lives one layer above each domain's `StatefulShellRoute`:
///
///   ShellRoute (this)
///   ├── financeShellRoute    (4 branches → DomainTabsShell)
///   ├── healthShellRoute     (3 branches → DomainTabsShell)
///   └── knowledgeShellRoute  (3 branches → DomainTabsShell)
///
/// Responsibilities the inner per-domain shells should *not* duplicate:
///   * share-intent lifecycle (mounts once, survives domain switches)
///   * `aiContextProvider` sync (route + domain, location-driven, global)
///   * root-level system back handling (pop → jump-to-home → exit-arm)
///   * domain dock chrome — desktop side dock only (≥ 600 px). Mobile
///     swaps the always-visible chip row for a per-page chevron in the
///     title; see `domain_switcher.dart`. [domainDockVisibleProvider]
///     still gates whether either presentation is rendered at all.
///   * `aiContextProvider.domain` — derived from the active route via
///     `domainForRoute`; the `askAi` helper reads this so no call site
///     needs to know which OS it's invoked from.
class AppDockShell extends ConsumerStatefulWidget {
  const AppDockShell({super.key, required this.child});

  final Widget child;

  static const double _tabletBreakpoint = 600;

  @override
  ConsumerState<AppDockShell> createState() => _AppDockShellState();
}

class _AppDockShellState extends ConsumerState<AppDockShell> {
  late final ShareIntentService _shareIntentService;
  bool _exitArmed = false;
  Timer? _exitResetTimer;
  static const Duration _exitWindow = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // §5.10.10 / S5c-native — app-wide share receiver. Self-guarded:
    // a no-op wherever the share channel is absent (tests / web /
    // desktop), so this is safe to start unconditionally here.
    _shareIntentService = ref.read(shareIntentServiceProvider);
    _shareIntentService.start();
  }

  @override
  void dispose() {
    _exitResetTimer?.cancel();
    _shareIntentService.stop();
    super.dispose();
  }

  /// Root back-button strategy. Defers steps 1–3 ("pop a pushed page /
  /// dismiss a modal / clear `?selected=`") to the shared [attemptBack]
  /// primitive so system back, the toolbar arrow, and the Esc shortcut
  /// stay in lockstep; only the app-shell-specific tail (tab-root jump,
  /// double-back-to-exit) lives here:
  ///  1–3. delegated to [attemptBack];
  ///  4. at any primary tab root other than Finance Home → jump to /
  ///     (treats Health tabs as primary roots; back from /health goes
  ///     to /home, matching the single-app exit model);
  ///  5. at Finance Home → double-back-to-exit.
  void _onSystemBack(bool didPop) {
    if (didPop) return;
    if (attemptBack(context)) return;
    final goRouter = GoRouter.of(context);
    final loc = goRouter.routeInformationProvider.value.uri.path;
    if (loc != AppRoutes.home && kPrimaryTabPaths.contains(loc)) {
      goRouter.go(AppRoutes.home);
      return;
    }
    if (_exitArmed) {
      _exitResetTimer?.cancel();
      SystemNavigator.pop();
      return;
    }
    _exitArmed = true;
    AppMessenger.show(
      context,
      ToastKind.info,
      AppLocalizations.of(context).pressBackAgainToExit,
    );
    _exitResetTimer?.cancel();
    _exitResetTimer = Timer(_exitWindow, () {
      if (mounted) _exitArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(aiContextProvider);
      final nextDomain = domainForRoute(location);
      if (current.path != location || current.domain != nextDomain) {
        ref.read(aiContextProvider.notifier).state = AiContext(
          path: location,
          domain: nextDomain,
        );
      }
    });

    final showDock = ref.watch(domainDockVisibleProvider);
    final specs = ref.watch(activeDomainShellsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onSystemBack(didPop),
      child: showDock
          ? _DockChrome(specs: specs, activePath: location, child: widget.child)
          : widget.child,
    );
  }
}

class _DockChrome extends StatelessWidget {
  const _DockChrome({
    required this.specs,
    required this.activePath,
    required this.child,
  });

  final List<DomainShellSpec> specs;
  final String activePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < AppDockShell._tabletBreakpoint;
        if (isCompact) {
          // Mobile: the per-page DomainSwitcherTitle (AppBar / FHeader)
          // is the only switch surface — keeps vertical space free.
          return child;
        }
        return Row(
          children: [
            _DesktopDock(specs: specs, activePath: activePath),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

void _switchToDomain(BuildContext context, DomainShellSpec spec) {
  final target = spec.tabs.isNotEmpty
      ? spec.tabs.first.routePath
      : AppRoutes.home;
  GoRouter.of(context).go(target);
}

class _DesktopDock extends ConsumerWidget {
  const _DesktopDock({required this.specs, required this.activePath});

  final List<DomainShellSpec> specs;
  final String activePath;

  static const double _width = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border, width: 1)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            for (final spec in specs)
              _DockIcon(
                spec: spec,
                selected: specOwnsPath(spec, activePath),
                onTap: () => _switchToDomain(context, spec),
              ),
            const Spacer(),
            _AskAiDockButton(onPress: () => askAi(context, ref)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Shell-level "Ask AI" affordance docked at the bottom of the desktop
/// rail. Always visible (not gated on multi-domain) so HealthOS /
/// KnowledgeOS users get the same one-tap entry FinanceOS has.
class _AskAiDockButton extends StatelessWidget {
  const _AskAiDockButton({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTooltip(
      tipBuilder: (_, _) =>
          Text(AppLocalizations.of(context).commandPaletteOpenAi),
      child: FTappable(
        onPress: onPress,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(FLucideIcons.sparkles, color: colors.primary, size: 20),
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final DomainShellSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    final fill =
        selected ? colors.primary.withValues(alpha: 0.10) : Colors.transparent;
    return FTooltip(
      tipBuilder: (_, _) => Text(spec.label),
      child: FTappable(
        onPress: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            selected ? spec.selectedIcon : spec.icon,
            color: iconColor,
            size: 22,
          ),
        ),
      ),
    );
  }
}

