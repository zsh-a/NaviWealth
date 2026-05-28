import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/command_palette/command_palette.dart';
import '../core/pwa/pwa_update_banner.dart';
import '../core/shortcuts/shortcuts.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/ui/ask_ai.dart';
import '../features/shared/forms/optimistic_form_submit.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';
import 'router.dart';
import 'shell_preferences.dart';

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
    final scaffoldMessengerKey = ref.watch(scaffoldMessengerKeyProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(compact: compact),
      darkTheme: AppTheme.dark(compact: compact),
      themeMode: themeMode,
      locale: locale,
      // Kept around for the few Material call sites still pushing
      // SnackBar/etc; will be removed once Phase 3 lands FToaster.
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext ctx, Widget? child) {
        // Pick a forui theme aligned with the active Material brightness
        // and the current platform. Forui ships separate touch/desktop
        // variants of each palette; route iOS / Android to .touch and
        // everything else to .desktop.
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final platform = isDark ? FThemes.slate.dark : FThemes.slate.light;
        final isTouch =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);
        final baseFTheme = isTouch ? platform.touch : platform.desktop;
        // Layer teal accent over Slate so the brand interaction color reads
        // calm-finance-teal instead of slate-grey. Also nudge the page
        // background off pure white into a cool gray (#F5F7F9) so soft
        // cards feel "lifted" against it — the previous near-white
        // background read as a bare canvas, washing out the SoftCard tint.
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
                ? baseFTheme.colors.background
                : const Color(0xFFF5F7F9),
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
        return FTheme(
          data: fTheme,
          child: MarketColorsScope(
            colors: marketColors,
            child: AppMessenger.init(
              child: GlobalShortcutsScope(
                onSwitchPrimaryTab: (int index) {
                  if (index < 0 || index >= kPrimaryTabPaths.length) return;
                  router.go(kPrimaryTabPaths[index]);
                },
                onOpenCommandPalette: (BuildContext invokeCtx) {
                  showCommandPalette(
                    invokeCtx,
                    commands: defaultCommandPaletteEntries(
                      AppLocalizations.of(invokeCtx),
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
                child: PwaUpdateBanner(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}
