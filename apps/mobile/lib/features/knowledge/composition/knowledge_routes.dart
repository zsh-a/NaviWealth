/// KnowledgeOS routing tree
/// (`docs/architecture/lifeos-shell.md` §3 + `docs/domains/knowledgeos-domain.md` §5).
///
/// Inbox and Library branches backed by [DomainTabsShell].
library;

import 'package:go_router/go_router.dart';

import '../../../core/shell/domain_tabs_shell.dart';
import '../../../design_system/widgets/form_leave_scope.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/knowledge_decision_detail_page.dart';
import '../ui/knowledge_inbox_page.dart';
import '../ui/knowledge_library_page.dart';
import '../ui/knowledge_note_detail_page.dart';
import 'knowledge_domain_shell.dart';
import 'knowledge_route_guard.dart';
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
            redirect: guardKnowledgeDetailChange,
            onExit: (context, _) => FormLeaveScope.confirmRouteLeave(
              context,
              path: KnowledgeRoutes.library,
            ),
            builder: (context, state) => const KnowledgeLibraryPage(),
            routes: [
              GoRoute(
                path: 'note/:id',
                name: KnowledgeRouteNames.noteDetail,
                onExit: (context, state) => FormLeaveScope.confirmRouteLeave(
                  context,
                  path: state.uri.path,
                ),
                builder: (context, state) => KnowledgeNoteDetailPage(
                  noteId: state.pathParameters['id'] ?? '',
                ),
              ),
              GoRoute(
                path: 'decision/:id',
                name: KnowledgeRouteNames.decisionDetail,
                onExit: (context, state) => FormLeaveScope.confirmRouteLeave(
                  context,
                  path: state.uri.path,
                ),
                builder: (context, state) => KnowledgeDecisionDetailPage(
                  decisionId: state.pathParameters['id'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
