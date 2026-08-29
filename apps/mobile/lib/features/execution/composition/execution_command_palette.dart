import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/execution_create_sheet.dart';
import 'execution_route_paths.dart';

List<CommandPaletteEntry> executionCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'create.execution',
      label: l10n.executionCreatePlanTitle,
      icon: FLucideIcons.plus,
      keywords: const <String>[
        'execution',
        'action',
        'plan',
        'project',
        'todo',
        'capture',
        '行动',
        '待办',
      ],
      run: (BuildContext ctx) => unawaited(showExecutionCreateSheet(ctx)),
    ),
    CommandPaletteEntry(
      id: 'nav.execution.today',
      label: l10n.executionCommandToday,
      icon: FLucideIcons.sun,
      keywords: <String>[
        ExecutionRoutes.today,
        'execution',
        'action',
        'todo',
        'today',
        l10n.executionCommandToday,
      ],
      run: (BuildContext ctx) => ctx.go(ExecutionRoutes.today),
    ),
    CommandPaletteEntry(
      id: 'nav.execution.commitments',
      label: l10n.executionCommandCommitments,
      icon: FLucideIcons.target,
      keywords: <String>[
        ExecutionRoutes.commitments,
        'execution',
        'commitment',
        'todo',
        'next action',
        l10n.executionCommandCommitments,
      ],
      run: (BuildContext ctx) => ctx.go(ExecutionRoutes.commitments),
    ),
  ];
}
