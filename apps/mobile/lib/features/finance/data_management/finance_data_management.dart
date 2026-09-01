import '../../../core/auth/domain_scope.dart';
import '../../../core/data_management/data_management.dart';
import '../../../core/sync/sync_table_registry.dart';

final DomainDataManagementSpec financeDataManagementSpec =
    DomainDataManagementSpec(
      scope: DomainScope.finance,
      label: 'FinanceOS',
      sourceTables: <DataTableSpec>[
        for (final table in syncDataTablesForPrefix(kFinanceDomainPrefix))
          if (_preservedFinanceTables.contains(table.table))
            DataTableSpec(
              table: table.table,
              ownerScoped: table.ownerScoped,
              hasTombstones: table.hasTombstones,
              preserveOnReset: true,
            )
          else
            table,
      ],
      cacheTables: const <DataTableSpec>[
        DataTableSpec(table: 'ingest_attachments', ownerScoped: true),
        DataTableSpec(table: 'ingest_drafts', ownerScoped: true),
        DataTableSpec(table: 'rebalance_execution_items', ownerScoped: true),
        DataTableSpec(table: 'rebalance_execution_sessions', ownerScoped: true),
        DataTableSpec(table: 'market_quotes'),
        DataTableSpec(table: 'market_history_bars'),
        DataTableSpec(table: 'market_symbol_searches'),
        DataTableSpec(table: 'market_corporate_action_candidates'),
        DataTableSpec(table: 'market_corporate_action_fetch_states'),
        DataTableSpec(
          table: 'watchlist_simulation_observations',
          ownerScoped: true,
        ),
        DataTableSpec(table: 'options_opportunity_cache', ownerScoped: true),
        DataTableSpec(
          table: 'recurring_pattern_observations',
          ownerScoped: true,
        ),
      ],
    );

const Set<String> _preservedFinanceTables = <String>{
  'users',
  'devices',
  'settings',
  'fx_rates',
};
