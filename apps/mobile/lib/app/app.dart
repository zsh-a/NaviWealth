import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/command_palette/command_palette.dart';
import '../core/perf/glass_quality_persistence.dart';
import '../core/perf/refresh_rate.dart';
import '../core/pwa/pwa_update_banner.dart';
import '../core/shortcuts/shortcuts.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/ui/ai_chat_sheet.dart';
import '../features/shared/forms/optimistic_form_submit.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';
import 'router.dart';
import 'shell_preferences.dart';

/// Vim-style `g`+key → route path mapping.
const Map<String, String> _kVimGotoRoutes = <String, String>{
  'home': AppRoutes.home,
  'portfolio': AppRoutes.portfolio,
  'activity': AppRoutes.activity,
  'plan': AppRoutes.plan,
  'ai': AppRoutes.ai,
  'settings': AppRoutes.settings,
};

class NaviWealthApp extends ConsumerWidget {
  const NaviWealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final compact = ref.watch(compactDensityProvider);
    final scaffoldMessengerKey = ref.watch(scaffoldMessengerKeyProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    // Restoring the previously settled quality lets the AdaptiveScope skip
    // its 3-second warm-up benchmark on every cold start. Without this, the
    // benchmark runs on each launch and starves frame budget — on Android
    // that surfaces as a black-screen first frame that recovers once
    // scrolling forces invalidation.
    final initialQuality = loadSavedGlassQuality(prefs);
    return LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      respectSystemAccessibility: true,
      // Match the adaptive scope's frame budget to the panel's actual
      // refresh rate (8 ms on ProMotion, 16 ms on 60 Hz). `allowStepUp`
      // lets the scope recover quality after thermal throttling subsides.
      // The package marks `GlassAdaptiveScopeConfig` @experimental for
      // threshold tuning, but the README recommends this exact wiring.
      adaptiveConfig: GlassAdaptiveScopeConfig( // ignore: experimental_member_use
        targetFrameMs: targetFrameBudgetMs(),
        allowStepUp: true,
        initialQuality: initialQuality,
        onQualityChanged: (_, to) => persistGlassQuality(prefs, to),
      ),
      child: ScrollingScope(
        child: GlassTheme(
        data: GlassThemeData(
          // Light: package default already supplies an icy cool blue-white
          // tint that reads well on white surfaces. We only customize the
          // brand glow.
          light: GlassThemeVariant.light.copyWith(
            glowColors: const GlassGlowColors(primary: ColorPalette.brand500),
          ),
          // Dark: package default has no glassColor, so cards visually
          // disappear against dark backgrounds. Adding a low-alpha white
          // tint plus a slightly stronger blur restores the iOS-style
          // frosted look on dark surfaces while keeping legibility.
          dark: GlassThemeVariant.dark.copyWith(
            glowColors: const GlassGlowColors(primary: ColorPalette.brand500),
            settings: const GlassThemeSettings(
              glassColor: Color(0x24FFFFFF),
              blur: 8.0,
              saturation: 1.15,
            ),
          ),
        ),
        // AdaptiveLiquidGlassLayer provides the LiquidGlassLayer +
        // (Impeller-only) BlendGroup that `LiquidGlass.grouped` looks
        // up when a glass widget renders premium quality with
        // `useOwnLayer: false`. Without this ancestor, premium grouped
        // surfaces silently render the child without any glass effect
        // in release builds, exposing the scaffold background.
        //
        // Sits inside `GlassTheme` so it can resolve default
        // settings/quality from the theme, and outside `MaterialApp`
        // so every route — including modals / dialogs pushed via the
        // root Navigator — inherits the same layer.
        child: AdaptiveLiquidGlassLayer(
          quality: GlassQuality.premium,
          child: MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(
            marketColorMode: marketMode,
            compact: compact,
          ),
          darkTheme: AppTheme.dark(
            marketColorMode: marketMode,
            compact: compact,
          ),
          themeMode: themeMode,
          locale: locale,
          // Global ScaffoldMessenger so optimistic-submit failures surface
          // a snackbar even after the originating form has popped (FIR-98).
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The shortcut scope wraps the navigator subtree so dialog routes
          // (e.g. the help dialog opened by `?`) are descendants of the
          // Shortcuts widget and `Esc` reaches the dismiss action. The PWA
          // update banner sits inside that scope so it stacks above all
          // routes on web; on non-web builds it's a transparent passthrough.
          builder: (BuildContext ctx, Widget? child) {
            return AppMessenger.init(
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
                    ),
                    onAskAi: (String query) =>
                        showAiChatSheet(invokeCtx, prefill: query),
                  );
                },
                onToggleSidebar: () =>
                    ref.read(sidebarCollapsedProvider.notifier).toggle(),
                onOpenAiChat: (BuildContext invokeCtx) =>
                    showAiChatSheet(invokeCtx),
                onVimGoto: (String target) {
                  final path = _kVimGotoRoutes[target];
                  if (path != null) router.go(path);
                },
                child: PwaUpdateBanner(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
        ),
        ),
      ),
      ),
    );
  }
}
