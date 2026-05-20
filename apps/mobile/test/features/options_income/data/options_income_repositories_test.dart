import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/options_income/data/approved_underlyings_repository.dart';
import 'package:naviwealth/features/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';

import '../../../data/db/test_database.dart';
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
    test('upsert(insert) persists row and queues insert op', () async {
      final draft = defaultProfileForMode(OptionsStrategyMode.balanced);

      final saved = await profileRepo.upsert(draft);

      // Re-stamped sync metadata.
      expect(saved.sync.ownerUserId, isNotEmpty);
      expect(saved.mode, OptionsStrategyMode.balanced);

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(1));
      expect(batch.single.tableName, 'options_strategy_profile');
      expect(batch.single.opType, OpType.insert);
      // Singleton: row id == owner_user_id.
      expect(batch.single.rowId, saved.sync.ownerUserId);
      expect(batch.single.fieldsDiff!['mode'], 'balanced');
      expect(batch.single.fieldsDiff!['only_on_approved_underlyings'], true);
    });

    test('second upsert produces update op, not insert', () async {
      await profileRepo.upsert(
        defaultProfileForMode(OptionsStrategyMode.balanced),
      );
      await outbox.ack((await outbox.peekBatch()).map((op) => op.opId));

      final loaded = await profileRepo.get('u-test');
      await profileRepo.upsert(
        loaded!.copyWith(
          riskDisclosureAckAt: DateTime.utc(2026, 5, 21),
        ),
      );

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(1));
      expect(batch.single.opType, OpType.update);
      // PK is never part of the update diff.
      expect(batch.single.fieldsDiff!.containsKey('user_id'), isFalse);
      expect(
        batch.single.fieldsDiff!['risk_disclosure_ack_at'],
        '2026-05-21T00:00:00.000Z',
      );
    });

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
    test('add persists row and queues insert op with composite id',
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

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(1));
      expect(batch.single.tableName, 'approved_underlyings');
      expect(batch.single.opType, OpType.insert);
      expect(batch.single.rowId, 'us_stock:AAPL');
      expect(batch.single.fieldsDiff!['symbol'], 'AAPL');
      expect(batch.single.fieldsDiff!['allow_put'], true);
    });

    test('update emits partial diff op', () async {
      final initial = await approvedRepo.add(
        symbol: 'MSFT',
        market: AssetMarket.usStock,
      );
      await outbox.ack((await outbox.peekBatch()).map((op) => op.opId));

      await approvedRepo.update(initial.copyWith(allowCall: false));

      final batch = await outbox.peekBatch();
      expect(batch.single.opType, OpType.update);
      expect(batch.single.fieldsDiff!['allow_call'], false);
      // Untouched fields are not in the diff (we ship a partial update).
      expect(batch.single.fieldsDiff!.containsKey('symbol'), isFalse);
    });

    test('remove writes tombstone and queues delete op', () async {
      final initial = await approvedRepo.add(
        symbol: 'NVDA',
        market: AssetMarket.usStock,
      );
      await outbox.ack((await outbox.peekBatch()).map((op) => op.opId));

      await approvedRepo.remove(initial);

      final batch = await outbox.peekBatch();
      expect(batch.single.opType, OpType.delete);
      expect(batch.single.fieldsDiff, isNull);

      // List queries omit the soft-deleted row.
      final active = await approvedRepo.listActive('u-test');
      expect(active, isEmpty);
    });
  });
}
