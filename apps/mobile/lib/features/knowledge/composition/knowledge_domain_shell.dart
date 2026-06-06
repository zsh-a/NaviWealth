/// KnowledgeOS `DomainShellSpec` registration
/// (`docs/lifeos-shell.md` §3 + `docs/knowledgeos-domain.md` §5).
///
/// Mirrors `features/health/composition/health_domain_shell.dart`.
/// 3 tabs: Inbox / Library / Review. Strings are literals for the
/// MVP — l10n keys land when the dogfood loop confirms wording.
library;

import 'package:forui/forui.dart';

import '../../../app/route_paths.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';

DomainShellSpec knowledgeDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.knowledge,
    label: 'KnowledgeOS',
    icon: FLucideIcons.brain,
    selectedIcon: FLucideIcons.brain,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.inbox,
        selectedIcon: FLucideIcons.inbox,
        label: l10n.knowledgeTabInbox,
        routePath: AppRoutes.knowledgeInbox,
      ),
      DomainShellTab(
        icon: FLucideIcons.bookOpen,
        selectedIcon: FLucideIcons.bookOpen,
        label: l10n.knowledgeTabLibrary,
        routePath: AppRoutes.knowledgeLibrary,
      ),
      DomainShellTab(
        icon: FLucideIcons.clipboardCheck,
        selectedIcon: FLucideIcons.clipboardCheck,
        label: l10n.knowledgeTabReview,
        routePath: AppRoutes.knowledgeReview,
      ),
    ],
  );
}
