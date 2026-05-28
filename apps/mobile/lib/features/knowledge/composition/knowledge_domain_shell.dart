/// KnowledgeOS `DomainShellSpec` registration
/// (`docs/lifeos-shell.md` §3 + `docs/knowledgeos-domain.md` §5).
///
/// Mirrors `features/health/composition/health_domain_shell.dart`.
/// 3 tabs: Inbox / Library / Review. Strings are literals for the
/// MVP — l10n keys land when the dogfood loop confirms wording.
library;

import 'package:flutter/material.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';

DomainShellSpec knowledgeDomainShell(AppLocalizations l10n) {
  return const DomainShellSpec(
    scope: DomainScope.knowledge,
    label: 'KnowledgeOS',
    icon: Icons.psychology_outlined,
    selectedIcon: Icons.psychology,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        label: 'Inbox',
        routePath: AppRoutes.knowledgeInbox,
      ),
      DomainShellTab(
        icon: Icons.library_books_outlined,
        selectedIcon: Icons.library_books,
        label: 'Library',
        routePath: AppRoutes.knowledgeLibrary,
      ),
      DomainShellTab(
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        label: 'Review',
        routePath: AppRoutes.knowledgeReview,
      ),
    ],
  );
}
