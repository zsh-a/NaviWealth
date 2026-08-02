import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/command_palette/command_palette_entry.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/knowledge_capture_sheet.dart';
import 'knowledge_route_paths.dart';

/// KnowledgeOS contributions to the shared Cmd-K command palette.
///
/// Mirrors `financeCommandPaletteEntries` so KnowledgeOS is reachable
/// from the palette like every other domain (it used to be a dead zone).
/// Capture / new-decision flows open ref-bound sheets rather than routes,
/// so they stay on the in-page FAB; the palette covers the three tab
/// destinations, which is what unblocks keyboard navigation into the
/// domain.
///
/// Labels come from l10n; keywords carry the route path plus English aliases
/// for locale-blind search.
List<CommandPaletteEntry> knowledgeCommandPaletteEntries(
  AppLocalizations l10n,
) {
  return <CommandPaletteEntry>[
    CommandPaletteEntry(
      id: 'create.knowledge.note',
      label: l10n.knowledgeCaptureTitle,
      icon: FLucideIcons.filePlus,
      keywords: const <String>['knowledge', 'capture', 'note'],
      run: (BuildContext ctx) => showKnowledgeCaptureSheet(ctx),
    ),
    CommandPaletteEntry(
      id: 'nav.knowledge.inbox',
      label: l10n.knowledgeCommandInbox,
      icon: FLucideIcons.inbox,
      keywords: <String>[
        KnowledgeRoutes.inbox,
        'knowledge',
        'inbox',
        'capture',
        'note',
        l10n.knowledgeCommandInbox,
        l10n.knowledgeInboxTitle,
        l10n.knowledgeSegmentNotes,
      ],
      run: (BuildContext ctx) => ctx.go(KnowledgeRoutes.inbox),
    ),
    CommandPaletteEntry(
      id: 'nav.knowledge.library',
      label: l10n.knowledgeCommandLibrary,
      icon: FLucideIcons.bookOpen,
      keywords: <String>[
        KnowledgeRoutes.library,
        'knowledge',
        'library',
        'decision',
        'concept',
        l10n.knowledgeCommandLibrary,
        l10n.knowledgeLibraryTitle,
        l10n.knowledgeSegmentDecisions,
        l10n.knowledgeSegmentConcepts,
      ],
      run: (BuildContext ctx) => ctx.go(KnowledgeRoutes.library),
    ),
    CommandPaletteEntry(
      id: 'nav.knowledge.review',
      label: l10n.knowledgeCommandReview,
      icon: FLucideIcons.scrollText,
      keywords: <String>[
        KnowledgeRoutes.review,
        'knowledge',
        'review',
        'reflect',
        l10n.knowledgeCommandReview,
        l10n.knowledgeReviewTitle,
      ],
      run: (BuildContext ctx) => ctx.go(KnowledgeRoutes.review),
    ),
  ];
}
