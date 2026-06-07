import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shortcuts/shortcut_help_dialog.dart';
import 'command_palette_entry.dart';

/// Build the shell-level command palette entries.
///
/// Pulls labels from [l10n] so search works in the user's language. Keywords
/// include the underlying route path so power users can match by URL.
///
/// [onToggleTheme] and [onToggleColorMode] are callbacks for the theme and
/// market-color-mode toggle actions. They are injected so the function stays
/// free of Riverpod dependencies and is easy to test.
///
/// [domainEntries] are the active domains' contributions composed by the
/// caller (e.g. `financeCommandPaletteEntries(l10n)` in app.dart). The
/// shell itself only knows system actions + the cross-domain home/settings
/// navigation so adding a new domain does not require editing this file.
List<CommandPaletteEntry> defaultCommandPaletteEntries(
  AppLocalizations l10n, {
  VoidCallback? onToggleTheme,
  VoidCallback? onToggleColorMode,
  VoidCallback? onToggleLanguage,
  void Function(BuildContext ctx)? onAskAi,
  List<CommandPaletteEntry> domainEntries = const <CommandPaletteEntry>[],
}) {
  return <CommandPaletteEntry>[
    // ── Navigation (cross-domain) ──
    CommandPaletteEntry(
      id: 'nav.home',
      label: l10n.commandPaletteGoOverview,
      icon: FLucideIcons.layoutDashboard,
      keywords: <String>[
        '/',
        'today',
        'overview',
        'home',
        l10n.commandPaletteGoOverview,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.home),
    ),
    ...domainEntries,
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: FLucideIcons.settings,
      keywords: <String>[
        AppRoutes.settings,
        'settings',
        l10n.commandPaletteGoSettings,
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settings),
    ),

    // ── Cross-domain AI ──
    if (onAskAi != null)
      CommandPaletteEntry(
        id: 'action.askAi',
        label: l10n.commandPaletteOpenAi,
        icon: FLucideIcons.sparkles,
        keywords: <String>[
          'ai',
          'ask',
          'assistant',
          'chat',
          l10n.commandPaletteOpenAi,
        ],
        run: onAskAi,
      ),
    CommandPaletteEntry(
      id: 'action.aiHistory',
      label: l10n.commandPaletteAiHistory,
      icon: FLucideIcons.bot,
      keywords: <String>[
        AppRoutes.settingsAiHistory,
        'ai',
        'history',
        'sessions',
        l10n.commandPaletteAiHistory,
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settingsAiHistory),
    ),

    // ── System actions ──
    if (onToggleTheme != null)
      CommandPaletteEntry(
        id: 'action.toggleTheme',
        label: l10n.commandPaletteToggleTheme,
        icon: FLucideIcons.sunMoon,
        keywords: <String>[
          'theme',
          'dark',
          'light',
          l10n.commandPaletteToggleTheme,
        ],
        run: (_) => onToggleTheme(),
      ),
    if (onToggleColorMode != null)
      CommandPaletteEntry(
        id: 'action.toggleColorMode',
        label: l10n.commandPaletteToggleColorMode,
        icon: FLucideIcons.palette,
        keywords: <String>[
          'color',
          'red',
          'green',
          'colorblind',
          l10n.commandPaletteToggleColorMode,
        ],
        run: (_) => onToggleColorMode(),
      ),
    if (onToggleLanguage != null)
      CommandPaletteEntry(
        id: 'action.toggleLanguage',
        label: l10n.commandPaletteToggleLanguage,
        icon: FLucideIcons.languages,
        keywords: <String>[
          'language',
          'locale',
          'en',
          'zh',
          l10n.commandPaletteToggleLanguage,
        ],
        run: (_) => onToggleLanguage(),
      ),
    CommandPaletteEntry(
      id: 'action.shortcutHelp',
      label: l10n.commandPaletteShortcutHelp,
      icon: FLucideIcons.keyboard,
      keywords: <String>['shortcuts', 'help', l10n.commandPaletteShortcutHelp],
      run: showShortcutHelpDialog,
    ),
  ];
}
