import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/options_income/data/approved_underlyings_repository.dart';
import 'package:naviwealth/features/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';
import '../../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late OptionsStrategyProfileRepository profileRepo;
  late ApprovedUnderlyingsRepository approvedRepo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    profileRepo = OptionsStrategyProfileRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    approvedRepo = ApprovedUnderlyingsRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('OptionsStrategyProfileRepository', () {
    test('upsert(insert) persists row and queues a dirty pointer', () async {
      final draft = defaultProfileForMode(OptionsStrategyMode.balanced);

      final saved = await profileRepo.upsert(draft);

      // Re-stamped sync metadata.
      expect(saved.sync.ownerUserId, isNotEmpty);
      expect(saved.mode, OptionsStrategyMode.balanced);

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'options_strategy_profile');
      // Singleton: row id == owner_user_id.
      expect(batch.single.rowId, saved.sync.ownerUserId);
    });

    test(
      'second upsert queues another dirty pointer at the same row',
      () async {
        await profileRepo.upsert(
          defaultProfileForMode(OptionsStrategyMode.balanced),
        );
        outbox.clearQueued();

        final loaded = await profileRepo.get('u-test');
        await profileRepo.upsert(
          loaded!.copyWith(riskDisclosureAckAt: DateTime.utc(2026, 5, 21)),
        );

        final batch = outbox.queued;
        expect(batch, hasLength(1));
        expect(batch.single.table, 'options_strategy_profile');
        expect(batch.single.rowId, loaded.sync.ownerUserId);
      },
    );

    test('watch streams the latest profile (or null when absent)', () async {
      final emissions = <bool>[];
      final sub = profileRepo
          .watch('u-test')
          .listen((p) => emissions.add(p != null));
      // Drift's `watchSingleOrNull` emits an initial snapshot synchronously
      // on first query. Yield a couple of microtasks so it lands.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emissions, isNotEmpty);
      expect(emissions.first, isFalse);

      await profileRepo.upsert(
        defaultProfileForMode(OptionsStrategyMode.aggressive),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isTrue);

      await sub.cancel();
    });
  });

  group('ApprovedUnderlyingsRepository', () {
    test(
      'add persists row and queues a dirty pointer with composite id',
      () async {
        final saved = await approvedRepo.add(
          symbol: 'aapl',
          market: AssetMarket.usStock,
        );

        // Symbol normalised to upper-case; id is `<market>:<symbol>`.
        expect(saved.symbol, 'AAPL');
        expect(saved.id, 'us_stock:AAPL');
        expect(saved.allowPut, isTrue);
        expect(saved.allowCall, isTrue);

        final batch = outbox.queued;
        expect(batch, hasLength(1));
        expect(batch.single.table, 'approved_underlyings');
        expect(batch.single.rowId, 'us_stock:AAPL');
      },
    );

    test('update queues a dirty pointer at the row', () async {
      final initial = await approvedRepo.add(
        symbol: 'MSFT',
        market: AssetMarket.usStock,
      );
      outbox.clearQueued();

      await approvedRepo.update(initial.copyWith(allowCall: false));

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'approved_underlyings');
      expect(batch.single.rowId, initial.id);
    });

    test('remove writes tombstone and queues a dirty pointer', () async {
      final initial = await approvedRepo.add(
        symbol: 'NVDA',
        market: AssetMarket.usStock,
      );
      outbox.clearQueued();

      await approvedRepo.remove(initial);

      final batch = outbox.queued;
      expect(batch, hasLength(1));
      expect(batch.single.table, 'approved_underlyings');
      expect(batch.single.rowId, initial.id);

      // List queries omit the soft-deleted row.
      final active = await approvedRepo.listActive('u-test');
      expect(active, isEmpty);
    });
  });
}
