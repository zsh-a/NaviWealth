import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/cashflow/composition/command_palette_contributions.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/rebalance/composition/command_palette_contributions.dart';

import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';

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
      id: 'nav.spending',
      label: l10n.spendingTitle,
      icon: FLucideIcons.pieChart,
      keywords: const <String>[
        FinanceRoutes.spending,
        'spending',
        'expenses',
        '支出分析',
      ],
      run: (BuildContext ctx) => ctx.go(FinanceRoutes.spending),
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
      id: 'action.corporateAction',
      label: l10n.corpActionTitle,
      icon: FLucideIcons.folderTree,
      keywords: <String>[
        FinanceRoutes.wealthCorporateAction,
        'corporate action',
        'dividend',
        'income',
        'withholding',
        'split',
        'drip',
        'rights issue',
        l10n.commandKeywordDividendCn,
        l10n.commandKeywordBonusDividendCn,
        l10n.commandKeywordWithholdingTaxCn,
        l10n.commandKeywordCorporateActionCn,
        l10n.commandKeywordSplitCn,
        l10n.commandKeywordRightsIssueCn,
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.wealthCorporateAction),
    ),
    CommandPaletteEntry(
      id: 'action.newCash',
      label: l10n.assetsAddCashTitle,
      icon: FLucideIcons.wallet,
      keywords: const <String>[
        FinanceRoutes.wealthNewCash,
        'cash',
        'balance',
        'deposit funds',
        '现金',
        '余额',
        '入金',
      ],
      run: (BuildContext ctx) => ctx.push(FinanceRoutes.wealthNewCash),
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
