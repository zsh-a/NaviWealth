import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../cashflow/command_palette_contributions.dart';
import '../../rebalance/command_palette_contributions.dart';

/// FinanceOS contributions to the shared command palette.
///
/// Shell-level `defaultCommandPaletteEntries` (`core/command_palette/`)
/// only ships system actions + the cross-domain home nav. Every Finance
/// route / quick action lives here so HealthOS / KnowledgeOS additions
/// land alongside as their own `<domain>CommandPaletteEntries(l10n)`
/// helpers without touching `core/`.
List<CommandPaletteEntry> financeCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.activity',
      label: l10n.navActivity,
      icon: FLucideIcons.receipt,
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
      icon: FLucideIcons.wallet,
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
      icon: FLucideIcons.lightbulb,
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
      icon: FLucideIcons.receipt,
      keywords: const <String>[AppRoutes.activityExpenses, 'expenses', '支出'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.activityExpenses),
    ),
    ...cashFlowCommandPaletteEntries(l10n),
    CommandPaletteEntry(
      id: 'nav.dividends',
      label: l10n.dividendCenterTitle,
      icon: FLucideIcons.creditCard,
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
      icon: FLucideIcons.chartPie,
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
      icon: FLucideIcons.flag,
      keywords: const <String>[AppRoutes.planFire, '/accounts/fire', 'fire'],
      run: (BuildContext ctx) => ctx.go(AppRoutes.planFire),
    ),
    CommandPaletteEntry(
      id: 'nav.incomePlanner',
      label: l10n.incomePlannerTitle,
      icon: FLucideIcons.candlestickChart,
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
      id: 'action.newTrade',
      label: l10n.commandPaletteNewTrade,
      icon: FLucideIcons.plus,
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
      icon: FLucideIcons.creditCard,
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
      icon: FLucideIcons.folderTree,
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
      icon: FLucideIcons.creditCard,
      keywords: const <String>[
        AppRoutes.expenseNew,
        'expense',
        'spend',
        '支出',
        '记一笔',
      ],
      run: (BuildContext ctx) => ctx.push(AppRoutes.expenseNew),
    ),
  ];
}
