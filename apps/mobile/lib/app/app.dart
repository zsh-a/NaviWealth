import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/providers.dart';
import '../core/shortcuts/shortcuts.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'router.dart';

class NaviWealthApp extends ConsumerWidget {
  const NaviWealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final marketMode = ref.watch(marketColorModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final logger = ref.watch(loggerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(marketColorMode: marketMode),
      darkTheme: AppTheme.dark(marketColorMode: marketMode),
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The shortcut scope wraps the navigator subtree so dialog routes
      // (e.g. the help dialog opened by Cmd/Ctrl+/) are descendants of
      // the Shortcuts widget and `Esc` reaches the dismiss action.
      builder: (BuildContext ctx, Widget? child) {
        return GlobalShortcutsScope(
          onSwitchPrimaryTab: (int index) {
            if (index < 0 || index >= kPrimaryTabPaths.length) return;
            router.go(kPrimaryTabPaths[index]);
          },
          onOpenCommandPalette: () => logger.i(
            'shortcut: command palette requested (UI ships in a follow-up)',
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
