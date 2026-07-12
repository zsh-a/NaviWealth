import '../../../core/auth/domain_scope.dart';
import '../../../core/data_management/data_management.dart';
import '../../../core/sync/sync_table_registry.dart';

final DomainDataManagementSpec executionDataManagementSpec =
    DomainDataManagementSpec(
      scope: DomainScope.execution,
      label: 'ExecutionOS',
      sourceTables: syncDataTablesForPrefix(kExecutionDomainPrefix),
    );
