import '../../../core/auth/domain_scope.dart';
import '../../../core/data_management/data_management.dart';
import '../../../core/sync/sync_table_registry.dart';

final DomainDataManagementSpec knowledgeDataManagementSpec =
    DomainDataManagementSpec(
      scope: DomainScope.knowledge,
      label: 'KnowledgeOS',
      sourceTables: syncDataTablesForPrefix(kKnowledgeDomainPrefix),
      cacheTables: const <DataTableSpec>[
        DataTableSpec(table: 'knowledge_inbox_triage', ownerScoped: true),
      ],
    );
