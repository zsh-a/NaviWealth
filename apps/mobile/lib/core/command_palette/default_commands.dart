import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
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
      run: (BuildContext ctx) => ctx.go(AppRoutes.home),
    ),
    CommandPaletteEntry(
      id: 'nav.activity',
      label: l10n.navActivity,
      icon: Icons.receipt_long_outlined,
      keywords: const <String>[
        AppRoutes.activity,
        'activity',
        'expenses',
        'transactions',
        '活动',
        '流水',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.activity),
    ),
    CommandPaletteEntry(
      id: 'nav.accounts',
      label: l10n.navAccounts,
      icon: Icons.account_balance_wallet_outlined,
      keywords: const <String>[
        AppRoutes.accounts,
        'accounts',
        'assets',
        'liabilities',
        'portfolio',
        '账户',
        '资产',
        '投资组合',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.accounts),
    ),
    CommandPaletteEntry(
      id: 'nav.expenses',
      label: l10n.navExpenses,
      icon: Icons.receipt_long_outlined,
      keywords: const <String>[AppRoutes.activityExpenses, 'expenses', '支出'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.activityExpenses),
    ),
    CommandPaletteEntry(
      id: 'nav.analytics',
      label: l10n.planAnalyticsTitle,
      icon: Icons.pie_chart_outline,
      keywords: const <String>[AppRoutes.accountsAnalytics, 'analytics', '分析'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.accountsAnalytics),
    ),
    CommandPaletteEntry(
      id: 'nav.fire',
      label: l10n.planFireTitle,
      icon: Icons.flag_outlined,
      keywords: const <String>[AppRoutes.accountsFire, 'fire'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.accountsFire),
    ),
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: Icons.settings_outlined,
      keywords: const <String>[AppRoutes.settings, 'settings', '设置'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.settings),
    ),

    // ── Actions ──
    CommandPaletteEntry(
      id: 'action.newTrade',
      label: l10n.commandPaletteNewTrade,
      icon: Icons.add_chart_outlined,
      keywords: const <String>[
        AppRoutes.tradeEntry,
        'trade',
        'buy',
        'sell',
        '交易',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.tradeEntry),
    ),
    CommandPaletteEntry(
      id: 'action.newDividend',
      label: l10n.corpActionTypeCashDividend,
      icon: Icons.payments_outlined,
      keywords: const <String>[
        AppRoutes.accountCorporateAction,
        'dividend',
        'income',
        'withholding',
        '股息',
        '分红',
        '代扣税',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.accountCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.corporateAction',
      label: l10n.corpActionTitle,
      icon: Icons.account_tree_outlined,
      keywords: const <String>[
        AppRoutes.accountCorporateAction,
        'corporate action',
        'split',
        'drip',
        'rights issue',
        '公司行动',
        '拆股',
        '配股',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.accountCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.newExpense',
      label: l10n.commandPaletteNewExpense,
      icon: Icons.add_card_outlined,
      keywords: const <String>[
        AppRoutes.expenseNew,
        'expense',
        'spend',
        '支出',
        '记一笔',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.expenseNew),
    ),
    CommandPaletteEntry(
      id: 'action.openAi',
      label: l10n.commandPaletteOpenAi,
      icon: Icons.smart_toy_outlined,
      keywords: const <String>[
        AppRoutes.settingsAiHistory,
        'ai',
        'assistant',
        'history',
        '助手',
        '历史',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settingsAiHistory),
    ),
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
