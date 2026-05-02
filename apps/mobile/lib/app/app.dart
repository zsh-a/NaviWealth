import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/command_palette/command_palette.dart';
import '../core/pwa/pwa_update_banner.dart';
import '../core/shortcuts/shortcuts.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/ui/ai_chat_sheet.dart';
import '../features/shared/forms/optimistic_form_submit.dart';
import '../l10n/gen/app_localizations.dart';
import 'router.dart';
import 'shell_preferences.dart';

/// Vim-style `g`+key → route path mapping.
const Map<String, String> _kVimGotoRoutes = <String, String>{
  'home': '/',
  'assets': '/assets',
  'ai': '/ai',
  'fire': '/fire',
  'settings': '/settings',
};

class NaviWealthApp extends ConsumerWidget {
  const NaviWealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final scaffoldMessengerKey = ref.watch(scaffoldMessengerKeyProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(marketColorMode: marketMode),
      darkTheme: AppTheme.dark(marketColorMode: marketMode),
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
        return GlobalShortcutsScope(
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
                  final next = MarketColorMode.values[
                      (MarketColorMode.values.indexOf(current) + 1) %
                          MarketColorMode.values.length];
                  ref.read(marketColorModeProvider.notifier).set(next);
                },
                onToggleLanguage: () {
                  ref.read(localeProvider.notifier).cycle();
                },
              ),
              onAskAi: (String query) => showAiChatSheet(
                invokeCtx,
                prefill: query,
              ),
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
        );
      },
    );
  }
}
