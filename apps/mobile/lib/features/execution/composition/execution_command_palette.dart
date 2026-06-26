import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';

List<CommandPaletteEntry> executionCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.execution.today',
      label: l10n.executionCommandToday,
      icon: FLucideIcons.sun,
      keywords: <String>[
        AppRoutes.executionToday,
        'execution',
        'action',
        'todo',
        'today',
        l10n.executionCommandToday,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.executionToday),
    ),
    CommandPaletteEntry(
      id: 'nav.execution.commitments',
      label: l10n.executionCommandCommitments,
      icon: FLucideIcons.target,
      keywords: <String>[
        AppRoutes.executionCommitments,
        'execution',
        'commitment',
        'todo',
        'next action',
        l10n.executionCommandCommitments,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.executionCommitments),
    ),
    CommandPaletteEntry(
      id: 'nav.execution.review',
      label: l10n.executionCommandReview,
      icon: FLucideIcons.clipboardCheck,
      keywords: <String>[
        AppRoutes.executionReview,
        'execution',
        'progress',
        'review',
        l10n.executionCommandReview,
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.executionReview),
    ),
  ];
}
