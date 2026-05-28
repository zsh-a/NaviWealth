import 'package:flutter/material.dart';
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
      icon: Icons.dashboard_outlined,
      keywords: const <String>['/', 'today', 'overview', 'home', '今日', '总览'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.home),
    ),
    ...domainEntries,
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: Icons.settings_outlined,
      keywords: const <String>[AppRoutes.settings, 'settings', '设置'],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settings),
    ),

    // ── Cross-domain AI ──
    if (onAskAi != null)
      CommandPaletteEntry(
        id: 'action.askAi',
        label: l10n.commandPaletteOpenAi,
        icon: Icons.auto_awesome_outlined,
        keywords: const <String>[
          'ai',
          'ask',
          'assistant',
          'chat',
          '问',
          '助手',
        ],
        run: onAskAi,
      ),
    CommandPaletteEntry(
      id: 'action.aiHistory',
      label: l10n.commandPaletteAiHistory,
      icon: Icons.smart_toy_outlined,
      keywords: const <String>[
        AppRoutes.settingsAiHistory,
        'ai',
        'history',
        'sessions',
        '历史',
        '会话',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settingsAiHistory),
    ),

    // ── System actions ──
    if (onToggleTheme != null)
      CommandPaletteEntry(
        id: 'action.toggleTheme',
        label: l10n.commandPaletteToggleTheme,
        icon: Icons.brightness_6_outlined,
        keywords: const <String>['theme', 'dark', 'light', '主题', '暗色', '亮色'],
        run: (_) => onToggleTheme(),
      ),
    if (onToggleColorMode != null)
      CommandPaletteEntry(
        id: 'action.toggleColorMode',
        label: l10n.commandPaletteToggleColorMode,
        icon: Icons.palette_outlined,
        keywords: const <String>[
          'color',
          'red',
          'green',
          'colorblind',
          '颜色',
          '涨跌',
          '色盲',
        ],
        run: (_) => onToggleColorMode(),
      ),
    if (onToggleLanguage != null)
      CommandPaletteEntry(
        id: 'action.toggleLanguage',
        label: l10n.commandPaletteToggleLanguage,
        icon: Icons.translate_outlined,
        keywords: const <String>[
          'language',
          'locale',
          'en',
          'zh',
          '语言',
          '切换语言',
        ],
        run: (_) => onToggleLanguage(),
      ),
    CommandPaletteEntry(
      id: 'action.shortcutHelp',
      label: l10n.commandPaletteShortcutHelp,
      icon: Icons.keyboard_outlined,
      keywords: const <String>['shortcuts', 'help', '快捷键'],
      run: showShortcutHelpDialog,
    ),
  ];
}
