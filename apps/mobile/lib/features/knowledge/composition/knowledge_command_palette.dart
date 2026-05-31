import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';

/// KnowledgeOS contributions to the shared Cmd-K command palette.
///
/// Mirrors `financeCommandPaletteEntries` so KnowledgeOS is reachable
/// from the palette like every other domain (it used to be a dead zone).
/// Capture / new-decision flows open ref-bound sheets rather than routes,
/// so they stay on the in-page FAB; the palette covers the three tab
/// destinations, which is what unblocks keyboard navigation into the
/// domain.
///
/// Labels stay literal (matching the domain shell, not yet localised);
/// keywords carry the route path plus English aliases for locale-blind
/// search.
List<CommandPaletteEntry> knowledgeCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'nav.knowledge.inbox',
      label: '知识 · 收件箱',
      icon: FLucideIcons.inbox,
      keywords: const <String>[
        AppRoutes.knowledgeInbox,
        'knowledge',
        'inbox',
        'capture',
        'note',
        '知识',
        '收件箱',
        '笔记',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.knowledgeInbox),
    ),
    CommandPaletteEntry(
      id: 'nav.knowledge.library',
      label: '知识 · 资料库',
      icon: FLucideIcons.bookOpen,
      keywords: const <String>[
        AppRoutes.knowledgeLibrary,
        'knowledge',
        'library',
        'decision',
        'concept',
        '知识',
        '资料库',
        '决策',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.knowledgeLibrary),
    ),
    CommandPaletteEntry(
      id: 'nav.knowledge.review',
      label: '知识 · 复盘',
      icon: FLucideIcons.scrollText,
      keywords: const <String>[
        AppRoutes.knowledgeReview,
        'knowledge',
        'review',
        'reflect',
        '知识',
        '复盘',
      ],
      run: (BuildContext ctx) => ctx.go(AppRoutes.knowledgeReview),
    ),
  ];
}
