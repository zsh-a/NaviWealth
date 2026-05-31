import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/command_palette/command_palette_entry.dart';
import '../../l10n/gen/app_localizations.dart';

List<CommandPaletteEntry> cashFlowCommandPaletteEntries(AppLocalizations l10n) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.cashflow',
      label: l10n.cashFlowCommandOpen,
      icon: FLucideIcons.chartColumnStacked,
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
      id: 'nav.income',
      label: l10n.cashFlowCommandViewIncome,
      icon: FLucideIcons.filter,
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
    CommandPaletteEntry(
      id: 'nav.cashflow.recurring',
      label: l10n.recurringCommandOpen,
      icon: FLucideIcons.calendarClock,
      keywords: <String>[
        AppRoutes.cashflowRecurring,
        'recurring',
        'subscription',
        'scheduled',
        l10n.commandKeywordRecurringCn,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.cashflowRecurring),
    ),
  ];
}
