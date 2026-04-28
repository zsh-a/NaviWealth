import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late int hlcCounter;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    hlcCounter = 0;
  });

  tearDown(() => db.close());

  Future<Hlc> stamp() async {
    hlcCounter++;
    return Hlc(
      wallMillis: 1_700_000_000_000 + hlcCounter,
      counter: 0,
      nodeId: 'test-device',
    );
  }

  LiabilityRepository repo({String Function()? id}) {
    return LiabilityRepository(
      db: db,
      ownerUserId: 'user-1',
      deviceId: 'test-device',
      stampHlc: stamp,
      idGenerator: id,
      clock: () => DateTime.utc(2026, 1, 1),
    );
  }

  Liability mortgage({String id = 'lia-1', String? accountId}) {
    return Liability(
      id: id,
      type: LiabilityType.mortgage,
      name: 'Home',
      principal: d('120000'),
      interestRate: d('0.05'),
      currency: 'CNY',
      paymentMethod: RepaymentMethod.equalPrincipal,
      termMonths: 12,
      startDate: DateTime.utc(2026, 1, 1),
      accountId: accountId,
      sync: SyncMeta(
        ownerUserId: '',
        updatedAt: DateTime.utc(2026, 1, 1),
        updatedByDevice: '',
        hlc: Hlc.zero('placeholder'),
      ),
    );
  }

  test('create persists liability and full amortization schedule', () async {
    var idCounter = 0;
    final r = repo(id: () => 'gen-${++idCounter}');
    await r.create(mortgage());

    final list = await r.watchAll().first;
    expect(list, hasLength(1));
    expect(list.single.name, 'Home');

    final schedule = await r.scheduleFor('lia-1');
    expect(schedule, hasLength(12));
    expect(schedule.first.periodIndex, 1);
    expect(schedule.last.periodIndex, 12);
    expect(schedule.last.remainingBalance, Decimal.zero);
  });

  test('credit card creates header without schedule', () async {
    final r = repo();
    final cc = Liability(
      id: 'cc-1',
      type: LiabilityType.creditCard,
      name: 'Visa',
      principal: d('0'),
      interestRate: d('0.18'),
      currency: 'CNY',
      statementDay: 5,
      paymentDueDay: 25,
      sync: SyncMeta(
        ownerUserId: '',
        updatedAt: DateTime.utc(2026, 1, 1),
        updatedByDevice: '',
        hlc: Hlc.zero('placeholder'),
      ),
    );
    // Credit card has no termMonths/startDate, so principal-positivity is the
    // only thing the model enforces — bump it just enough to satisfy the
    // calculator's invariant should the schedule path ever fire.
    await r.create(cc.copyWith(principal: d('1')));
    final schedule = await r.scheduleFor('cc-1');
    expect(schedule, isEmpty);
  });

  test('registerPayment marks period paid and writes a transaction', () async {
    final r = repo();
    await r.create(mortgage(accountId: 'acc-1'));

    final txId = await r.registerPayment(
      liabilityId: 'lia-1',
      periodIndex: 1,
    );
    expect(txId, isNotEmpty);

    final schedule = await r.scheduleFor('lia-1');
    expect(schedule.first.paidAt, isNotNull);
    expect(schedule[1].paidAt, isNull);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.type, TransactionType.liabilityPayment);
    expect(txs.single.accountId, 'acc-1');
    expect(txs.single.currency, 'CNY');
  });

  test('registerPayment refuses to mark a period twice', () async {
    final r = repo();
    await r.create(mortgage(accountId: 'acc-1'));
    await r.registerPayment(liabilityId: 'lia-1', periodIndex: 1);
    expect(
      () => r.registerPayment(liabilityId: 'lia-1', periodIndex: 1),
      throwsA(isA<StateError>()),
    );
  });

  test('registerPayment requires accountId on the liability', () async {
    final r = repo();
    await r.create(mortgage());
    expect(
      () => r.registerPayment(liabilityId: 'lia-1', periodIndex: 1),
      throwsA(isA<StateError>()),
    );
  });
}
