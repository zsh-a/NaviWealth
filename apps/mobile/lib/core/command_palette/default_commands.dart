import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../features/cashflow/command_palette_contributions.dart';
import '../../features/rebalance/command_palette_contributions.dart';
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
      keywords: const <String>['/', 'today', 'overview', 'home', '今日', '总览'],
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
      id: 'nav.wealth',
      label: l10n.navWealth,
      icon: Icons.account_balance_wallet_outlined,
      keywords: const <String>[
        AppRoutes.wealth,
        // Legacy keyword kept so users typing "/accounts" still find the
        // canonical Wealth tab.
        '/accounts',
        'wealth',
        'accounts',
        'assets',
        'liabilities',
        'portfolio',
        '账户',
        '资产',
        '投资组合',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.wealth),
    ),
    CommandPaletteEntry(
      id: 'nav.plan',
      label: l10n.navPlan,
      icon: Icons.insights_outlined,
      keywords: const <String>[
        AppRoutes.plan,
        'plan',
        'fire',
        'goals',
        'scenarios',
        '规划',
        '计划',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.plan),
    ),
    CommandPaletteEntry(
      id: 'nav.expenses',
      label: l10n.navExpenses,
      icon: Icons.receipt_long_outlined,
      keywords: const <String>[AppRoutes.activityExpenses, 'expenses', '支出'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.activityExpenses),
    ),
    ...cashFlowCommandPaletteEntries(l10n),
    CommandPaletteEntry(
      id: 'nav.dividends',
      label: l10n.dividendCenterTitle,
      icon: Icons.payments_outlined,
      keywords: <String>[
        AppRoutes.cashflowDividends,
        'dividends',
        'passive income',
        l10n.commandKeywordDividendCenterCn,
        l10n.commandKeywordMyDividendsCn,
        l10n.commandKeywordPassiveIncomeCn,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.cashflowDividends),
    ),
    CommandPaletteEntry(
      id: 'nav.projection',
      label: l10n.planAnalyticsTitle,
      icon: Icons.pie_chart_outline,
      keywords: const <String>[
        AppRoutes.planProjection,
        '/accounts/analytics',
        'analytics',
        'projection',
        '分析',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.planProjection),
    ),
    CommandPaletteEntry(
      id: 'nav.fire',
      label: l10n.planFireTitle,
      icon: Icons.flag_outlined,
      keywords: const <String>[AppRoutes.planFire, '/accounts/fire', 'fire'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.planFire),
    ),
    CommandPaletteEntry(
      id: 'nav.incomePlanner',
      label: l10n.incomePlannerTitle,
      icon: Icons.candlestick_chart_outlined,
      keywords: <String>[
        AppRoutes.planIncome,
        '/accounts/income',
        'income planner',
        'options',
        'sell put',
        'covered call',
        l10n.commandKeywordOptionsCn,
        l10n.commandKeywordCashFlowCn,
        l10n.commandKeywordSellPutCn,
        l10n.commandKeywordCoveredCallCn,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.planIncome),
    ),
    ...rebalanceCommandPaletteEntries(l10n),
    CommandPaletteEntry(
      id: 'nav.settings',
      label: l10n.commandPaletteGoSettings,
      icon: Icons.settings_outlined,
      keywords: const <String>[AppRoutes.settings, 'settings', '设置'],
      run: (BuildContext ctx) => ctx.push(AppRoutes.settings),
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
      keywords: <String>[
        AppRoutes.wealthCorporateAction,
        'dividend',
        'income',
        'withholding',
        l10n.commandKeywordDividendCn,
        l10n.commandKeywordBonusDividendCn,
        l10n.commandKeywordWithholdingTaxCn,
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.wealthCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.corporateAction',
      label: l10n.corpActionTitle,
      icon: Icons.account_tree_outlined,
      keywords: <String>[
        AppRoutes.wealthCorporateAction,
        'corporate action',
        'split',
        'drip',
        'rights issue',
        l10n.commandKeywordCorporateActionCn,
        l10n.commandKeywordSplitCn,
        l10n.commandKeywordRightsIssueCn,
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.wealthCorporateAction),
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
