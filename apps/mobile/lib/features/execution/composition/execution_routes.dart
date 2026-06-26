import 'package:go_router/go_router.dart';

import '../../../app/domain_tabs_shell.dart';
import '../../../app/route_paths.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../ui/execution_commitments_page.dart';
import '../ui/execution_review_page.dart';
import '../ui/execution_today_page.dart';
import 'execution_domain_shell.dart';

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
            path: AppRoutes.executionToday,
            name: AppRouteNames.executionToday,
            builder: (context, state) => const ExecutionTodayPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.executionCommitments,
            name: AppRouteNames.executionCommitments,
            builder: (context, state) => const ExecutionCommitmentsPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoutes.executionReview,
            name: AppRouteNames.executionReview,
            builder: (context, state) => const ExecutionReviewPage(),
          ),
        ],
      ),
    ],
  );
}
