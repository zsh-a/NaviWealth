import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/command_palette/command_palette.dart';
import '../core/pwa/pwa_update_banner.dart';
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
      // the Shortcuts widget and `Esc` reaches the dismiss action. The
      // PWA update banner sits inside that scope so it stacks above all
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
              ),
            );
          },
          child: PwaUpdateBanner(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
