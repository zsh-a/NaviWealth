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
      keywords: const <String>[
        AppRoutes.cashflow,
        'cashflow',
        'cash flow',
        'income',
        'dividend',
        '\u73b0\u91d1\u6d41',
        '\u6536\u5165',
        '\u80a1\u606f',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.cashflow),
    ),
    CommandPaletteEntry(
      id: 'action.newIncome',
      label: l10n.cashFlowCommandNewIncome,
      icon: Icons.add_circle_outline,
      keywords: const <String>[
        'income',
        'salary',
        'dividend',
        'cashflow',
        '\u6536\u5165',
        '\u5de5\u8d44',
        '\u80a1\u606f',
      ],
      run: (BuildContext ctx) => ctx.go('${AppRoutes.activity}?kinds=income'),
    ),
  ];
}
