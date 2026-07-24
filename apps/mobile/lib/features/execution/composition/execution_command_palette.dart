import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/execution_action_sheet.dart';
import '../ui/execution_commitment_sheet.dart';
import '../ui/execution_project_sheet.dart';
import 'execution_route_paths.dart';

List<CommandPaletteEntry> executionCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'create.execution.action',
      label: l10n.executionCreateActionTitle,
      icon: FLucideIcons.listPlus,
      keywords: const <String>[
        'execution',
        'action',
        'todo',
        'capture',
        '行动',
        '待办',
      ],
      run: (BuildContext ctx) =>
          unawaited(showExecutionActionSheet(context: ctx)),
    ),
    CommandPaletteEntry(
      id: 'create.execution.project',
      label: l10n.executionCreateProjectTitle,
      icon: FLucideIcons.folderPlus,
      keywords: const <String>['execution', 'project', '项目'],
      run: (BuildContext ctx) =>
          unawaited(showExecutionProjectSheet(context: ctx)),
    ),
    CommandPaletteEntry(
      id: 'create.execution.commitment',
      label: l10n.executionCreateCommitmentTitle,
      icon: FLucideIcons.target,
      keywords: const <String>['execution', 'commitment', '承诺'],
      run: (BuildContext ctx) =>
          unawaited(showExecutionCommitmentSheet(context: ctx)),
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
    CommandPaletteEntry(
      id: 'nav.execution.review',
      label: l10n.executionCommandReview,
      icon: FLucideIcons.clipboardCheck,
      keywords: <String>[
        ExecutionRoutes.review,
        'execution',
        'progress',
        'review',
        l10n.executionCommandReview,
      ],
      run: (BuildContext ctx) => ctx.go(ExecutionRoutes.review),
    ),
  ];
}
