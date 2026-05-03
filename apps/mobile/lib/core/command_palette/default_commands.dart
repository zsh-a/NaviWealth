import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../shortcuts/shortcut_help_dialog.dart';
import 'command_palette_entry.dart';

/// Build the default command palette entries.
///
/// Pulls labels from [l10n] so search works in the user's language. Keywords
/// include the underlying route path so power users can match by URL.
///
/// [onToggleTheme] and [onToggleColorMode] are callbacks for the theme and
/// market-color-mode toggle actions. They are injected so the function stays
/// free of Riverpod dependencies and is easy to test.
List<CommandPaletteEntry> defaultCommandPaletteEntries(
  AppLocalizations l10n, {
  VoidCallback? onToggleTheme,
  VoidCallback? onToggleColorMode,
  VoidCallback? onToggleLanguage,
}) {
  return <CommandPaletteEntry>[
    // ── Navigation ──
    CommandPaletteEntry(
      id: 'nav.home',
      label: l10n.commandPaletteGoOverview,
      icon: Icons.dashboard_outlined,
      keywords: const <String>['/', 'overview', 'home', '总览'],
      run: (BuildContext ctx) => ctx.go('/'),
    ),
    CommandPaletteEntry(
      id: 'nav.portfolio',
      label: l10n.navPortfolio,
      icon: Icons.account_balance_wallet_outlined,
      keywords: const <String>['/portfolio', 'portfolio', 'assets', '资产', '投资组合'],
      run: (BuildContext ctx) => ctx.go('/portfolio'),
    ),
    CommandPaletteEntry(
      id: 'nav.ai',
      label: l10n.navAI,
      icon: Icons.smart_toy_outlined,
      keywords: const <String>['/ai', 'ai', 'assistant', 'AI', '助手'],
      run: (BuildContext ctx) => ctx.go('/ai'),
    ),
    CommandPaletteEntry(
      id: 'nav.accounts',
      label: l10n.commandPaletteGoAccounts,
      icon: Icons.account_balance_outlined,
      keywords: const <String>['/accounts', 'accounts', '账户'],
      run: (BuildContext ctx) => ctx.go('/portfolio/accounts'),
    ),
    CommandPaletteEntry(
      id: 'nav.expenses',
      label: l10n.commandPaletteGoExpenses,
      icon: Icons.receipt_long_outlined,
      keywords: const <String>['/expenses', 'expenses', '支出'],
      run: (BuildContext ctx) => ctx.go('/portfolio/expenses'),
    ),
    CommandPaletteEntry(
      id: 'nav.analytics',
      label: l10n.commandPaletteGoAnalytics,
      icon: Icons.pie_chart_outline,
      keywords: const <String>['/analytics', 'analytics', '分析'],
      run: (BuildContext ctx) => ctx.go('/analytics'),
    ),
    CommandPaletteEntry(
      id: 'nav.fire',
      label: l10n.commandPaletteGoFire,
      icon: Icons.flag_outlined,
      keywords: const <String>['/fire', 'fire'],
      run: (BuildContext ctx) => ctx.go('/analytics/fire'),
    ),
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: Icons.settings_outlined,
      keywords: const <String>['/settings', 'settings', '设置'],
      run: (BuildContext ctx) => ctx.go('/settings'),
    ),

    // ── Actions ──
    CommandPaletteEntry(
      id: 'action.newTrade',
      label: l10n.commandPaletteNewTrade,
      icon: Icons.add_chart_outlined,
      keywords: const <String>['/portfolio/trade', 'trade', 'buy', 'sell', '交易'],
      run: (BuildContext ctx) => ctx.push('/portfolio/trade'),
    ),
    CommandPaletteEntry(
      id: 'action.newExpense',
      label: l10n.commandPaletteNewExpense,
      icon: Icons.add_card_outlined,
      keywords: const <String>[
        '/expenses/new',
        'expense',
        'spend',
        '支出',
        '记一笔',
      ],
      run: (BuildContext ctx) => ctx.push('/portfolio/expenses/new'),
    ),
    CommandPaletteEntry(
      id: 'action.openAi',
      label: l10n.commandPaletteOpenAi,
      icon: Icons.smart_toy_outlined,
      keywords: const <String>['/ai', 'ai', 'assistant', '助手'],
      run: (BuildContext ctx) => ctx.push('/ai'),
    ),
    if (onToggleTheme != null)
      CommandPaletteEntry(
        id: 'action.toggleTheme',
        label: l10n.commandPaletteToggleTheme,
        icon: Icons.brightness_6_outlined,
        keywords: const <String>[
          'theme',
          'dark',
          'light',
          '主题',
          '暗色',
          '亮色',
        ],
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
