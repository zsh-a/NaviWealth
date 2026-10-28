import '../../../core/auth/domain_scope.dart';
import '../../../core/data_management/data_management.dart';
import '../../../core/sync/sync_table_registry.dart';

final DomainDataManagementSpec knowledgeDataManagementSpec =
    DomainDataManagementSpec(
      scope: DomainScope.knowledge,
      label: 'KnowledgeOS',
      sourceTables: [
        ...syncDataTablesForPrefix(kKnowledgeDomainPrefix),
        const DataTableSpec(
          table: 'knowledge_source_connections',
          ownerScoped: true,
        ),
      ],
      cacheTables: const <DataTableSpec>[
        DataTableSpec(table: 'knowledge_source_cache', ownerScoped: true),
        DataTableSpec(
          table: 'knowledge_source_import_leases',
          ownerScoped: true,
        ),
      ],
    );
