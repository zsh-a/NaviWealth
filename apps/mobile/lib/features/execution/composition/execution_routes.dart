import 'package:go_router/go_router.dart';

import '../../../core/shell/domain_tabs_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/execution_commitments_page.dart';
import '../ui/execution_detail_page.dart';
import '../ui/execution_review_page.dart';
import '../ui/execution_today_page.dart';
import 'execution_domain_shell.dart';
import 'execution_route_paths.dart';

StatefulShellRoute executionShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => DomainTabsShell(
      shell: shell,
      spec: executionDomainShell(AppLocalizations.of(context)),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ExecutionRoutes.today,
            name: ExecutionRouteNames.today,
            builder: (context, state) => const ExecutionTodayPage(),
            routes: [
              GoRoute(
                path: 'action/:id',
                name: ExecutionRouteNames.actionDetail,
                builder: (context, state) => ExecutionActionDetailPage(
                  actionId: state.pathParameters['id'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ExecutionRoutes.commitments,
            name: ExecutionRouteNames.commitments,
            builder: (context, state) => const ExecutionCommitmentsPage(),
            routes: [
              GoRoute(
                path: 'projects/:id',
                name: ExecutionRouteNames.projectDetail,
                builder: (context, state) => ExecutionProjectDetailPage(
                  projectId: state.pathParameters['id'] ?? '',
                ),
              ),
              GoRoute(
                path: ':id',
                name: ExecutionRouteNames.commitmentDetail,
                builder: (context, state) => ExecutionCommitmentDetailPage(
                  commitmentId: state.pathParameters['id'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ExecutionRoutes.review,
            name: ExecutionRouteNames.review,
            builder: (context, state) => const ExecutionReviewPage(),
          ),
        ],
      ),
    ],
  );
}
