import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/command_palette/command_palette.dart';
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

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(marketColorMode: marketMode, compact: compact),
      darkTheme: AppTheme.dark(marketColorMode: marketMode, compact: compact),
      themeMode: themeMode,
      locale: locale,
      // Global ScaffoldMessenger so optimistic-submit failures surface
      // a snackbar even after the originating form has popped (FIR-98).
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext ctx, Widget? child) {
        // Pick a Forui theme aligned with the active Material brightness
        // and the current platform. Forui ships separate touch/desktop
        // variants of each palette; we route iOS / Android to .touch and
        // everything else to .desktop. Forui widgets read FThemeData via
        // FTheme while Material widgets keep reading Theme.of(context).
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final platform = isDark ? FThemes.zinc.dark : FThemes.zinc.light;
        final isTouch = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android);
        final fTheme = isTouch ? platform.touch : platform.desktop;
        return FTheme(
          data: fTheme,
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
          ),
        );
      },
    );
  }
}
