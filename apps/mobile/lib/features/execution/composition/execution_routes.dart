import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../app/route_paths.dart';
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
            name: AppRouteNames.executionToday,
            builder: (context, state) => const ExecutionTodayPage(),
            routes: [
              GoRoute(
                path: 'action/:id',
                name: AppRouteNames.executionActionDetail,
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
            name: AppRouteNames.executionCommitments,
            builder: (context, state) => const ExecutionCommitmentsPage(),
            routes: [
              GoRoute(
                path: ':id',
                name: AppRouteNames.executionCommitmentDetail,
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
            name: AppRouteNames.executionReview,
            builder: (context, state) => const ExecutionReviewPage(),
          ),
        ],
      ),
    ],
  );
}
