import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/sync/domain_generation.dart';
import 'package:naviwealth/features/settings/data_management/data_reset_coordinator.dart';

import '../../core/persistence/test_database.dart';
import '../../core/sync/_fake_api.dart';

void main() {
  test(
    'reset all everywhere advances and persists every domain generation',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final specs = <DomainDataManagementSpec>[];
      for (final scope in DomainScope.values) {
        final table = 'reset_${scope.wire}';
        await db.customStatement(
          'CREATE TABLE $table ('
          'id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL)',
        );
        await db.customStatement('INSERT INTO $table VALUES (?, ?)', <Object?>[
          '${scope.wire}-row',
          'user-a',
        ]);
        specs.add(
          DomainDataManagementSpec(
            scope: scope,
            label: scope.wire,
            sourceTables: <DataTableSpec>[
              DataTableSpec(table: table, ownerScoped: true),
            ],
          ),
        );
      }
      final service = DataManagementService(
        database: db,
        ownerUserId: 'user-a',
        specs: specs,
      );
      final api = FakeSyncApiClient();
      final generations = InMemoryDomainGenerationStore();
      final coordinator = DataResetCoordinator(
        service: service,
        api: api,
        generations: generations,
        scheduler: null,
      );

      final result = await coordinator.resetAllEverywhere();

      expect(result.affected, 4);
      expect(result.generations, <String, int>{
        for (final scope in DomainScope.values) scope.wire: 1,
      });
      expect(await generations.readAll(), result.generations);
      for (final scope in DomainScope.values) {
        final row = await db
            .customSelect('SELECT COUNT(*) AS c FROM reset_${scope.wire}')
            .getSingle();
        expect(row.read<int>('c'), 0);
      }
    },
  );
}
