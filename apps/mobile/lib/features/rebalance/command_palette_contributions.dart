import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/command_palette/command_palette_entry.dart';
import '../../l10n/gen/app_localizations.dart';
import 'ui/target_allocation_editor_sheet.dart';

List<CommandPaletteEntry> rebalanceCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.rebalance',
      label: l10n.rebalanceCommandOpen,
      icon: FLucideIcons.scale,
      keywords: <String>[
        AppRoutes.planRebalance,
        '/accounts/rebalance',
        'rebalance',
        'allocation',
        'portfolio drift',
        l10n.commandKeywordRebalanceCn,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.planRebalance),
    ),
    CommandPaletteEntry(
      id: 'action.rebalance.targetAllocation',
      label: l10n.rebalanceCommandAdjustTarget,
      icon: FLucideIcons.slidersHorizontal,
      keywords: <String>[
        'target allocation',
        'custom target',
        'portfolio weights',
        'allocation weights',
        l10n.commandKeywordTargetAllocationCn,
        l10n.commandKeywordRebalanceCn,
      ],
      run: (BuildContext ctx) => showTargetAllocationEditorSheet(context: ctx),
    ),
  ];
}
