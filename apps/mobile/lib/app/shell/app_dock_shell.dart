import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/composition/ai_context.dart';
import '../../core/ai/composition/ask_ai.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/domain_shell.dart';
import '../../design_system/design_system.dart';
import '../../features/settings/ui/ai/ai_privacy_onboarding.dart';
import '../../l10n/gen/app_localizations.dart';
import '../routing/route_paths.dart';
import '../share_intents/share_intent_service.dart';

/// Outer multi-domain shell (`docs/architecture/lifeos-shell.md` §3 Option B, D-2.3b).
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
///   * root-level system back handling (pop → exit-arm)
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

  @override
  ConsumerState<AppDockShell> createState() => _AppDockShellState();
}

class _AppDockShellState extends ConsumerState<AppDockShell> {
  late final ShareIntentService _shareIntentService;

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
    _shareIntentService.stop();
    super.dispose();
  }

  /// Root back-button strategy. Defers steps 1–3 ("pop a pushed page /
  /// dismiss a modal / clear `?selected=`") to the shared [attemptBack]
  /// primitive so system back, the toolbar arrow, and the Esc shortcut
  /// stay in lockstep; only the app-shell-specific tail (root exit
  /// confirmation) lives here:
  ///  1–3. delegated to [attemptBack];
  ///  4. at any primary tab root → fall through to
  ///     [ExitConfirmingSystemBackScope].
  bool _handleSystemBackBeforeExit(BuildContext context) {
    if (attemptBack(context)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(aiContextProvider);
      final nextDomain = domainForRoute(
        ref.read(domainPackRegistryProvider),
        location,
      );
      if (current.path != location || current.domain != nextDomain) {
        ref.read(aiContextProvider.notifier).state = AiContext(
          path: location,
          domain: nextDomain,
        );
      }
    });

    final showDock = ref.watch(domainDockVisibleProvider);
    final specs = ref.watch(activeDomainShellsProvider);
    final shellChild = showDock
        ? _DockChrome(specs: specs, activePath: location, child: widget.child)
        : widget.child;

    return ExitConfirmingSystemBackScope(
      onBack: _handleSystemBackBeforeExit,
      disarmKey: location,
      child: _ShellGlobalMounts(child: shellChild),
    );
  }
}

class _ShellGlobalMounts extends StatelessWidget {
  const _ShellGlobalMounts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        const IgnorePointer(child: AiPrivacyOnboardingMount()),
      ],
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
        final viewportWidth = MediaQuery.sizeOf(context).width;
        if (viewportWidth < Breakpoints.mobile) {
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

  static const double _width = AppSpacing.s56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          right: BorderSide(color: colors.border, width: AppStroke.hairline),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.s12),
            // Life hub (Phase B spatial layer) sits above domain workspaces.
            _LifeDockIcon(
              selected:
                  activePath == AppRoutes.life ||
                  activePath.startsWith('${AppRoutes.life}/'),
              onTap: () {
                AppInteraction.signal(AppInteractionIntent.navigate);
                GoRouter.of(context).go(AppRoutes.life);
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            const _DockGroupDivider(),
            const SizedBox(height: AppSpacing.s4),
            for (final spec in specs)
              _DockIcon(
                spec: spec,
                selected: specOwnsPath(spec, activePath),
                onTap: () => _switchToDomain(context, spec),
              ),
            const Spacer(),
            const _DockGroupDivider(),
            const SizedBox(height: AppSpacing.s8),
            _AskAiDockButton(onPress: () => askAi(context, ref)),
            const SizedBox(height: AppSpacing.s12),
          ],
        ),
      ),
    );
  }
}

/// Shell-level assistant affordance docked at the bottom of the desktop
/// rail. Always visible (not gated on multi-domain) so HealthOS /
/// KnowledgeOS users get the same one-tap entry FinanceOS has.
class _AskAiDockButton extends StatelessWidget {
  const _AskAiDockButton({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return AppIconButton.softPrimaryRing(
      icon: FLucideIcons.sparkles,
      tooltip: AppLocalizations.of(context).commandPaletteOpenAi,
      onPress: onPress,
      size: AppSpacing.s48,
      iconSize: AppIconSizes.mlg,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
    );
  }
}

class _DockGroupDivider extends StatelessWidget {
  const _DockGroupDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: AppSpacing.s24,
      height: AppSpacing.hairline,
      decoration: BoxDecoration(
        color: colors.border.withValues(alpha: AppOpacity.medium),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    );
  }
}

class _LifeDockIcon extends StatelessWidget {
  const _LifeDockIcon({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return AppIconButton(
      icon: FLucideIcons.house,
      tooltip: l10n.lifeNavLabel,
      onPress: onTap,
      size: AppSpacing.s40,
      iconSize: AppIconSizes.mlg,
      iconColor: selected ? colors.primary : colors.mutedForeground,
      surface: selected
          ? AppIconButtonSurface.softSelected
          : AppIconButtonSurface.plain,
      borderRadius: AppRadius.md,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
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
    return AppIconButton(
      icon: selected ? spec.selectedIcon : spec.icon,
      tooltip: spec.label,
      onPress: onTap,
      size: AppSpacing.s40,
      iconSize: AppIconSizes.mlg,
      iconColor: selected ? colors.primary : colors.mutedForeground,
      surface: selected
          ? AppIconButtonSurface.softSelected
          : AppIconButtonSurface.plain,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
    );
  }
}
