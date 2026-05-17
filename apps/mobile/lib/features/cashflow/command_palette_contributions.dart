import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/command_palette/command_palette_entry.dart';
import '../../l10n/gen/app_localizations.dart';

List<CommandPaletteEntry> cashFlowCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.cashflow',
      label: l10n.cashFlowCommandOpen,
      icon: Icons.waterfall_chart_outlined,
      keywords: <String>[
        AppRoutes.cashflow,
        'cashflow',
        'cash flow',
        'income',
        'dividend',
        l10n.commandKeywordCashFlowCn,
        l10n.commandKeywordIncomeCn,
        l10n.commandKeywordDividendCn,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.cashflow),
    ),
    CommandPaletteEntry(
      id: 'action.newIncome',
      label: l10n.cashFlowCommandNewIncome,
      icon: Icons.add_circle_outline,
      keywords: <String>[
        'income',
        'salary',
        'dividend',
        'cashflow',
        l10n.commandKeywordIncomeCn,
        l10n.commandKeywordSalaryCn,
        l10n.commandKeywordDividendCn,
      ],
      run: (BuildContext ctx) => ctx.go('${AppRoutes.activity}?kinds=income'),
    ),
  ];
}
