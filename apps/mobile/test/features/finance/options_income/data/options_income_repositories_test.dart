import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/options_income/data/leaps_call_position_repository.dart';
import 'package:naviwealth/features/finance/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/finance/options_income/data/trade_journal_repository.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late OptionsStrategyProfileRepository profileRepo;
  late TradeJournalRepository journalRepo;
  late LeapsCallPositionRepository leapsRepo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    profileRepo = OptionsStrategyProfileRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    journalRepo = TradeJournalRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    leapsRepo = LeapsCallPositionRepository(
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

    test('get only returns the profile for the requested owner', () async {
      await profileRepo.upsert(
        defaultProfileForMode(OptionsStrategyMode.aggressive),
      );

      expect(await profileRepo.get('u-test'), isNotNull);
      expect(await profileRepo.get('other-user'), isNull);
    });
  });

  group('TradeJournalRepository', () {
    test('round-trips lifecycle, quantity, and fee fields', () async {
      final expiration = DateTime.utc(2026, 8, 21);
      final saved = await journalRepo.create(
        underlyingAssetId: 'nasdaq:AAPL',
        strategy: OptionsStrategyKind.cashSecuredPut,
        symbol: 'AAPL',
        optionSymbol: 'AAPL260821P00200000',
        openedAt: DateTime.utc(2026, 7, 20),
        expirationAt: expiration,
        entryCredit: Decimal.fromInt(125),
        fees: Decimal.parse('2.50'),
        contractQuantity: 3,
        currency: 'USD',
      );

      final loaded = await journalRepo.get(saved.id);
      expect(loaded, isNotNull);
      expect(loaded!.expirationAt?.toUtc(), expiration);
      expect(loaded.fees, Decimal.parse('2.50'));
      expect(loaded.contractQuantity, 3);
      expect(loaded.grossEntryCredit, Decimal.fromInt(375));
    });
  });

  group('LeapsCallPositionRepository', () {
    test('round-trips, updates, and queues the synced row pointer', () async {
      outbox.clearQueued();
      final saved = await leapsRepo.create(
        underlyingAssetId: 'nasdaq:AAPL',
        symbol: 'aapl',
        optionSymbol: 'AAPL280121C00180000',
        openedAt: DateTime.utc(2026, 7, 20),
        expirationAt: DateTime.utc(2028, 1, 21),
        strikePrice: Decimal.fromInt(180),
        entryDebit: Decimal.fromInt(1200),
        fees: Decimal.parse('2.50'),
        currentMark: Decimal.fromInt(1250),
        currentDelta: Decimal.parse('0.72'),
      );

      expect(saved.symbol, 'AAPL');
      expect(saved.grossEntryCost, Decimal.parse('1202.50'));
      expect(outbox.queued.single.table, 'options_leaps_call_positions');

      final loaded = await leapsRepo.get(saved.id);
      expect(loaded?.currentDelta, Decimal.parse('0.72'));
      final updated = await leapsRepo.update(
        loaded!.copyWith(currentMark: Decimal.fromInt(1400)),
      );
      expect(updated.currentMark, Decimal.fromInt(1400));
      expect(
        (await leapsRepo.get(saved.id))?.currentMark,
        Decimal.fromInt(1400),
      );
    });
  });
}
