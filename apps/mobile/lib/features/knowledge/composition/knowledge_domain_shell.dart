/// KnowledgeOS `DomainShellSpec` registration
/// (`docs/architecture/lifeos-shell.md` §3 + `docs/domains/knowledgeos-domain.md` §5).
///
/// Mirrors `features/health/composition/health_domain_shell.dart`.
/// 2 tabs: Inbox / Library. Review remains available from contextual signals
/// and the command palette instead of consuming permanent navigation space.
/// chrome stays consistent with FinanceOS and HealthOS.
library;

import 'package:forui/forui.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'knowledge_route_paths.dart';

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
        routePath: KnowledgeRoutes.inbox,
      ),
      DomainShellTab(
        icon: FLucideIcons.bookOpen,
        selectedIcon: FLucideIcons.bookOpen,
        label: l10n.knowledgeTabLibrary,
        routePath: KnowledgeRoutes.library,
      ),
    ],
  );
}
