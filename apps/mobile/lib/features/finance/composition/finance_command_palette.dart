import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';

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
        FinanceRoutes.activity,
        'activity',
        'expenses',
        'transactions',
        '活动',
        '流水',
      ],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.activity),
    ),
    CommandPaletteEntry(
      id: 'nav.wealth',
      label: l10n.navWealth,
      icon: FLucideIcons.wallet,
      keywords: const <String>[
        FinanceRoutes.wealth,
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
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.wealth),
    ),
    CommandPaletteEntry(
      id: 'nav.plan',
      label: l10n.navPlan,
      icon: FLucideIcons.lightbulb,
      keywords: const <String>[FinanceRoutes.plan, 'plan', 'fire', '规划', '计划'],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.plan),
    ),
    CommandPaletteEntry(
      id: 'nav.expenses',
      label: l10n.navExpenses,
      icon: FLucideIcons.receipt,
      keywords: const <String>[
        FinanceRoutes.activityExpenses,
        'expenses',
        '支出',
      ],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.activityExpenses),
    ),
    ...cashFlowCommandPaletteEntries(l10n),
    CommandPaletteEntry(
      id: 'nav.dividends',
      label: l10n.dividendCenterTitle,
      icon: FLucideIcons.creditCard,
      keywords: <String>[
        FinanceRoutes.cashflowDividends,
        'dividends',
        'passive income',
        l10n.commandKeywordDividendCenterCn,
        l10n.commandKeywordMyDividendsCn,
        l10n.commandKeywordPassiveIncomeCn,
      ],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.cashflowDividends),
    ),
    CommandPaletteEntry(
      id: 'nav.fire',
      label: l10n.planFireTitle,
      icon: FLucideIcons.flag,
      keywords: const <String>[
        FinanceRoutes.planFire,
        '/accounts/fire',
        'fire',
      ],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.planFire),
    ),
    CommandPaletteEntry(
      id: 'nav.incomePlanner',
      label: l10n.incomePlannerTitle,
      icon: FLucideIcons.candlestickChart,
      keywords: <String>[
        FinanceRoutes.planIncome,
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
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.planIncome),
    ),
    ...rebalanceCommandPaletteEntries(l10n),
    CommandPaletteEntry(
      id: 'action.newTrade',
      label: l10n.commandPaletteNewTrade,
      icon: FLucideIcons.plus,
      keywords: const <String>[
        FinanceRoutes.tradeEntry,
        'trade',
        'buy',
        'sell',
        '交易',
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.tradeEntry),
    ),
    CommandPaletteEntry(
      id: 'action.newDividend',
      label: l10n.corpActionTypeCashDividend,
      icon: FLucideIcons.creditCard,
      keywords: <String>[
        FinanceRoutes.wealthCorporateAction,
        'dividend',
        'income',
        'withholding',
        l10n.commandKeywordDividendCn,
        l10n.commandKeywordBonusDividendCn,
        l10n.commandKeywordWithholdingTaxCn,
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.wealthCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.corporateAction',
      label: l10n.corpActionTitle,
      icon: FLucideIcons.folderTree,
      keywords: <String>[
        FinanceRoutes.wealthCorporateAction,
        'corporate action',
        'split',
        'drip',
        'rights issue',
        l10n.commandKeywordCorporateActionCn,
        l10n.commandKeywordSplitCn,
        l10n.commandKeywordRightsIssueCn,
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.wealthCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.newExpense',
      label: l10n.commandPaletteNewExpense,
      icon: FLucideIcons.creditCard,
      keywords: const <String>[
        FinanceRoutes.expenseNew,
        'expense',
        'spend',
        '支出',
        '记一笔',
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.expenseNew),
    ),
  ];
}
