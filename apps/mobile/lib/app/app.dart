import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/ai/composition/ask_ai.dart';
import '../core/command_palette/command_palette.dart';
import '../core/lifeos/domain_pack.dart';
import '../core/pwa/pwa_update_banner.dart';
import '../core/security/biometric_lock_gate.dart';
import '../core/shell/shell_preferences.dart';
import '../core/shortcuts/shortcuts.dart';
import '../core/update/native_update_banner.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'domain_composition.dart';
import 'route_paths.dart';
import 'router.dart';

/// Vim-style `g`+key → route path mapping.
///
/// Mnemonics align with the 4-tab IA (Today / Activity / Wealth / Plan):
///   g h / g t → Today, g a → Activity, g n / g w → Wealth,
///   g p → Plan, g s → Settings (off-nav global).
const Map<String, String> _kVimGotoRoutes = <String, String>{
  'home': AppRoutes.home,
  'today': AppRoutes.home,
  'activity': AppRoutes.activity,
  'accounts': AppRoutes.wealth,
  'wealth': AppRoutes.wealth,
  'plan': AppRoutes.plan,
  'settings': AppRoutes.settings,
};

class NaviWealthApp extends ConsumerWidget {
  const NaviWealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final compact = useCompactDensity(defaultTargetPlatform, kIsWeb);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(compact: compact),
      darkTheme: AppTheme.dark(compact: compact),
      themeMode: themeMode,
      locale: locale,
      routerConfig: router,
      onNavigationNotification: _claimSystemBack,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext ctx, Widget? child) {
        // Pick a forui theme aligned with the active Material brightness
        // and the current platform. Forui ships separate touch/desktop
        // variants of each palette; route iOS / Android to .touch and
        // everything else to .desktop.
        final platformBrightness = MediaQuery.platformBrightnessOf(ctx);
        final isDark = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformBrightness == Brightness.dark,
        };
        final platform = isDark ? FThemes.slate.dark : FThemes.slate.light;
        final isTouch =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);
        final baseFTheme = isTouch ? platform.touch : platform.desktop;
        // Layer cyan brand accent over Slate and override the page
        // background + text colors to match the fintech spec:
        //   Light: cool-white (#F8FCFC), navy text, cyan accent.
        //   Dark:  deep navy (#0A1F28), light navy text, bright cyan accent.
        //
        // Forui 0.22 dropped `colors` from `FThemeData.copyWith` — colour
        // overrides now require rebuilding via the factory constructor.
        final brightness = isDark ? Brightness.dark : Brightness.light;
        final fTheme = FThemeData(
          touch: isTouch,
          colors: baseFTheme.colors.copyWith(
            primary: AccentColors.primary(brightness),
            primaryForeground: AccentColors.onPrimary(brightness),
            background: isDark
                ? ColorPalette.navy950
                : ColorPalette.neutralGlass,
            foreground: isDark ? ColorPalette.navy50 : ColorPalette.navy900,
            mutedForeground: isDark
                ? ColorPalette.navy400
                : ColorPalette.navy400,
            card: isDark ? ColorPalette.navyGlass : ColorPalette.neutral0,
            border: isDark
                ? ColorPalette.navy800
                : ColorPalette.neutralGlassBorder,
            muted: isDark ? ColorPalette.navyGlass : ColorPalette.neutralTint,
          ),
        );
        // Sync brightnessProvider so marketColorsProvider derives correctly.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final current = ref.read(brightnessProvider);
          final resolved = isDark ? Brightness.dark : Brightness.light;
          if (current != resolved) {
            ref.read(brightnessProvider.notifier).state = resolved;
          }
        });
        final marketColors = ref.watch(marketColorsProvider);
        return _AndroidSystemBackOwner(
          child: FTheme(
            data: fTheme,
            child: MarketColorsScope(
              colors: marketColors,
              child: AppMessenger.init(
                child: GlobalShortcutsScope(
                  onSwitchPrimaryTab: (int index) {
                    final paths = ref.read(primaryTabPathsProvider);
                    if (index < 0 || index >= paths.length) return;
                    router.go(paths[index]);
                  },
                  onOpenCommandPalette: (BuildContext invokeCtx) {
                    showCommandPalette(
                      invokeCtx,
                      commands: defaultCommandPaletteEntries(
                        AppLocalizations.of(invokeCtx),
                        homePath: AppRoutes.home,
                        settingsPath: AppRoutes.settings,
                        aiHistoryPath: AppRoutes.settingsAiHistory,
                        onToggleTheme: () {
                          final current = ref.read(themeModeProvider);
                          final next = current == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark;
                          ref.read(themeModeProvider.notifier).set(next);
                        },
                        onToggleColorMode: () {
                          final current = ref.read(marketColorModeProvider);
                          final next =
                              MarketColorMode.values[(MarketColorMode.values
                                          .indexOf(current) +
                                      1) %
                                  MarketColorMode.values.length];
                          ref.read(marketColorModeProvider.notifier).set(next);
                        },
                        onToggleLanguage: () {
                          ref.read(localeProvider.notifier).cycle();
                        },
                        onAskAi: (BuildContext ctx) => askAi(ctx, ref),
                        // Every active domain contributes its palette
                        // entries, merged in domain order — the same
                        // aggregation pattern as device tools / prompt
                        // blocks (`activeDomainPacksProvider`). HealthOS /
                        // KnowledgeOS used to be Cmd-K dead zones; this
                        // wires them in alongside Finance automatically.
                        domainEntries: domainCommandPaletteEntries(
                          ref.read(activeDomainPacksProvider),
                          AppLocalizations.of(invokeCtx),
                        ),
                      ),
                      onAskAi: (String query) =>
                          askAi(invokeCtx, ref, prefill: query),
                    );
                  },
                  onToggleSidebar: () =>
                      ref.read(sidebarCollapsedProvider.notifier).toggle(),
                  onOpenAiChat: (BuildContext invokeCtx) =>
                      askAi(invokeCtx, ref),
                  onVimGoto: (String target) {
                    final path = _kVimGotoRoutes[target];
                    if (path != null) router.go(path);
                  },
                  child: BiometricLockGate(
                    child: NativeUpdateBanner(
                      child: PwaUpdateBanner(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _claimSystemBack(NavigationNotification notification) {
  // Flutter 3.44 lets Android predictive/global back bypass the framework
  // when the current navigator reports no pop handler. NaviWealth owns root
  // back globally, so Android must always route the gesture into Flutter.
  if (defaultTargetPlatform == TargetPlatform.android) {
    unawaited(SystemNavigator.setFrameworkHandlesBack(true));
    return true;
  }
  unawaited(SystemNavigator.setFrameworkHandlesBack(notification.canHandlePop));
  return true;
}

class _AndroidSystemBackOwner extends StatefulWidget {
  const _AndroidSystemBackOwner({required this.child});

  final Widget child;

  @override
  State<_AndroidSystemBackOwner> createState() =>
      _AndroidSystemBackOwnerState();
}

class _AndroidSystemBackOwnerState extends State<_AndroidSystemBackOwner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _claim();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _claim();
  }

  void _claim() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(SystemNavigator.setFrameworkHandlesBack(true));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
