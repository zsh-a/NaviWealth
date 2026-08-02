import 'package:forui/forui.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/shell/domain_shell.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'execution_route_paths.dart';

DomainShellSpec executionDomainShell(AppLocalizations l10n) {
  return DomainShellSpec(
    scope: DomainScope.execution,
    label: 'ExecutionOS',
    icon: FLucideIcons.listTodo,
    selectedIcon: FLucideIcons.listTodo,
    tabs: <DomainShellTab>[
      DomainShellTab(
        icon: FLucideIcons.sun,
        selectedIcon: FLucideIcons.sun,
        label: l10n.executionTabToday,
        routePath: ExecutionRoutes.today,
      ),
      DomainShellTab(
        icon: FLucideIcons.target,
        selectedIcon: FLucideIcons.target,
        label: l10n.executionTabCommitments,
        routePath: ExecutionRoutes.commitments,
      ),
    ],
  );
}
