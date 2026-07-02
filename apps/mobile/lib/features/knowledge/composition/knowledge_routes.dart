/// KnowledgeOS routing tree
/// (`docs/architecture/lifeos-shell.md` §3 + `docs/domains/knowledgeos-domain.md` §5).
///
/// Mirrors `features/health/composition/health_routes.dart`. 3
/// branches (Inbox / Library / Review) backed by [DomainTabsShell].
library;

import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/knowledge_decision_detail_page.dart';
import '../ui/knowledge_inbox_page.dart';
import '../ui/knowledge_library_page.dart';
import '../ui/knowledge_object_detail_page.dart';
import '../ui/knowledge_review_page.dart';
import 'knowledge_domain_shell.dart';
import 'knowledge_route_paths.dart';

StatefulShellRoute knowledgeShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => DomainTabsShell(
      shell: shell,
      spec: knowledgeDomainShell(AppLocalizations.of(context)),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: KnowledgeRoutes.inbox,
            name: KnowledgeRouteNames.inbox,
            builder: (context, state) => const KnowledgeInboxPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: KnowledgeRoutes.library,
            name: KnowledgeRouteNames.library,
            builder: (context, state) => const KnowledgeLibraryPage(),
            routes: [
              GoRoute(
                path: 'decision/:id',
                name: KnowledgeRouteNames.decisionDetail,
                builder: (context, state) => KnowledgeDecisionDetailPage(
                  decisionId: state.pathParameters['id'] ?? '',
                ),
              ),
              GoRoute(
                path: 'object/:kind/:id',
                name: KnowledgeRouteNames.objectDetail,
                builder: (context, state) => KnowledgeObjectDetailPage(
                  kind: state.pathParameters['kind'] ?? '',
                  id: state.pathParameters['id'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: KnowledgeRoutes.review,
            name: KnowledgeRouteNames.review,
            builder: (context, state) => const KnowledgeReviewPage(),
          ),
        ],
      ),
    ],
  );
}
