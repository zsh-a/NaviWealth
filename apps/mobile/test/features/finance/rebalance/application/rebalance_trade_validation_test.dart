import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_trade_validation.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

import '../../../../core/persistence/test_database.dart';
import '../data/rebalance_execution_test_fixtures.dart';

void main() {
  test('snapshot validation rejects every semantic mismatch branch', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final validation = RebalanceTradeValidation(db);
    final base = testRequest('item-1');
    final buy = testPlan(reverseCollections: true).trades.first;

    void expectCode(
      RebalanceExecutionRequest request,
      SuggestedTrade suggestion,
      RebalanceTradeValidationCode code,
    ) {
      expect(
        () => validation.validateSnapshot(_item(request, suggestion)),
        throwsA(
          isA<RebalanceTradeValidationError>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }

    expectCode(
      _request(base, type: TradeType.sell),
      buy,
      RebalanceTradeValidationCode.directionMismatch,
    );
    expectCode(
      base,
      SuggestedTrade(
        category: buy.category,
        direction: buy.direction,
        amount: buy.amount,
        assetId: 'us_stock:MSFT',
      ),
      RebalanceTradeValidationCode.assetTargetMismatch,
    );
    expectCode(
      base,
      SuggestedTrade(
        category: AssetCategory.crypto,
        direction: buy.direction,
        amount: buy.amount,
        assetId: base.asset.id,
      ),
      RebalanceTradeValidationCode.categoryMismatch,
    );
    expectCode(
      _request(base, asset: base.asset.copyWith(type: AssetType.realEstate)),
      SuggestedTrade(
        category: AssetCategory.realEstate,
        direction: buy.direction,
        amount: buy.amount,
        assetId: base.asset.id,
      ),
      RebalanceTradeValidationCode.unsupportedAsset,
    );
    expectCode(
      _request(base, asset: base.asset.copyWith(market: 'US')),
      buy,
      RebalanceTradeValidationCode.assetInvalid,
    );
    expectCode(
      _request(base, asset: base.asset.copyWith(id: '')),
      SuggestedTrade(
        category: buy.category,
        direction: buy.direction,
        amount: buy.amount,
      ),
      RebalanceTradeValidationCode.assetInvalid,
    );
    expectCode(
      _request(base, asset: base.asset.copyWith(symbol: '')),
      buy,
      RebalanceTradeValidationCode.assetInvalid,
    );
    expectCode(
      _request(
        base,
        asset: base.asset.copyWith(
          sync: base.asset.sync.copyWith(ownerUserId: 'owner-b'),
        ),
      ),
      buy,
      RebalanceTradeValidationCode.ownerMismatch,
    );
  });

  test(
    'fresh validation rejects every live reference failure branch',
    () async {
      for (final scenario in _FreshScenario.values) {
        final db = makeTestDatabase();
        try {
          await _seedFreshScenario(db, scenario);
          final validation = RebalanceTradeValidation(db);
          final request = testRequest('item-1');
          final item = _item(
            request,
            testPlan(reverseCollections: true).trades.first,
          );

          await expectLater(
            db.transactionWithScope(
              (scope) => validation.validateFresh(scope, item),
            ),
            throwsA(
              isA<RebalanceTradeValidationError>().having(
                (error) => error.code,
                'code for ${scenario.name}',
                scenario.expected,
              ),
            ),
            reason: scenario.name,
          );
        } finally {
          await db.close();
        }
      }
    },
  );

  test('broker account may execute a trade in another currency', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await _seedFreshScenario(db, _FreshScenario.cashWrongCurrency);
    await (db.update(db.accounts)
          ..where((row) => row.id.equals('broker-account')))
        .write(const AccountsCompanion(currency: Value('CNY')));
    final base = testRequest('item-1');
    final request = RebalanceExecutionRequest(
      transactionId: base.transactionId,
      account: Account(
        id: base.account.id,
        type: base.account.type,
        name: base.account.name,
        currency: 'CNY',
        category: base.account.category,
        sync: base.account.sync,
      ),
      cashAccount: null,
      asset: base.asset,
      type: base.type,
      quantity: base.quantity,
      price: base.price,
      currency: base.currency,
      tradeDate: base.tradeDate,
      fee: base.fee,
      tax: base.tax,
      note: base.note,
    );
    final item = _item(
      request,
      testPlan(reverseCollections: true).trades.first,
    );
    final validation = RebalanceTradeValidation(db);

    expect(validation.validateSnapshot(item).cashAccountId, isNull);
    await db.transactionWithScope(
      (scope) => validation.validateFresh(scope, item),
    );
  });
}

RebalanceExecutionItem _item(
  RebalanceExecutionRequest request,
  SuggestedTrade suggestion,
) => RebalanceExecutionItem(
  id: request.transactionId,
  sessionId: 'session-1',
  ownerUserId: 'owner-a',
  position: 0,
  suggestion: suggestion,
  request: request,
  state: RebalanceExecutionItemState.ready,
  createdAt: testNow,
  updatedAt: testNow,
);

RebalanceExecutionRequest _request(
  RebalanceExecutionRequest base, {
  Account? account,
  Account? cashAccount,
  Asset? asset,
  TradeType? type,
}) => RebalanceExecutionRequest(
  transactionId: base.transactionId,
  account: account ?? base.account,
  cashAccount: cashAccount ?? base.cashAccount,
  asset: asset ?? base.asset,
  type: type ?? base.type,
  quantity: base.quantity,
  price: base.price,
  currency: base.currency,
  tradeDate: base.tradeDate,
  fee: base.fee,
  tax: base.tax,
  note: base.note,
);

enum _FreshScenario {
  assetMissing(RebalanceTradeValidationCode.assetInvalid),
  assetDeleted(RebalanceTradeValidationCode.assetInvalid),
  assetForeign(RebalanceTradeValidationCode.assetInvalid),
  assetMutated(RebalanceTradeValidationCode.assetInvalid),
  primaryMissing(RebalanceTradeValidationCode.accountInvalid),
  primaryDeleted(RebalanceTradeValidationCode.accountInvalid),
  primaryArchived(RebalanceTradeValidationCode.accountInvalid),
  primaryForeign(RebalanceTradeValidationCode.accountInvalid),
  primaryNonAsset(RebalanceTradeValidationCode.accountInvalid),
  cashMissing(RebalanceTradeValidationCode.cashAccountInvalid),
  cashDeleted(RebalanceTradeValidationCode.cashAccountInvalid),
  cashArchived(RebalanceTradeValidationCode.cashAccountInvalid),
  cashForeign(RebalanceTradeValidationCode.cashAccountInvalid),
  cashNonAsset(RebalanceTradeValidationCode.cashAccountInvalid),
  cashWrongCurrency(RebalanceTradeValidationCode.cashAccountInvalid);

  const _FreshScenario(this.expected);
  final RebalanceTradeValidationCode expected;
}

Future<void> _seedFreshScenario(AppDatabase db, _FreshScenario scenario) async {
  if (scenario != _FreshScenario.primaryMissing) {
    await _insertAccount(
      db,
      id: 'broker-account',
      type: scenario == _FreshScenario.primaryNonAsset
          ? AccountCategory.liability
          : AccountCategory.broker,
      side: scenario == _FreshScenario.primaryNonAsset
          ? AccountSide.liability
          : AccountSide.asset,
      owner: scenario == _FreshScenario.primaryForeign ? 'owner-b' : 'owner-a',
      currency: 'USD',
      archived: scenario == _FreshScenario.primaryArchived,
      deleted: scenario == _FreshScenario.primaryDeleted,
    );
  }
  if (scenario != _FreshScenario.cashMissing) {
    await _insertAccount(
      db,
      id: 'cash-account',
      type: scenario == _FreshScenario.cashNonAsset
          ? AccountCategory.liability
          : AccountCategory.cash,
      side: scenario == _FreshScenario.cashNonAsset
          ? AccountSide.liability
          : AccountSide.asset,
      owner: scenario == _FreshScenario.cashForeign ? 'owner-b' : 'owner-a',
      currency: scenario == _FreshScenario.cashWrongCurrency ? 'EUR' : 'USD',
      archived: scenario == _FreshScenario.cashArchived,
      deleted: scenario == _FreshScenario.cashDeleted,
    );
  }
  if (scenario != _FreshScenario.assetMissing) {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'us_stock:AAPL',
            type: AssetType.stock,
            symbol: 'AAPL',
            currency: scenario == _FreshScenario.assetMutated ? 'EUR' : 'USD',
            market: const Value('us_stock'),
            ownerUserId: scenario == _FreshScenario.assetForeign
                ? 'owner-b'
                : 'owner-a',
            updatedAt: testNow,
            updatedByDevice: 'device-a',
            hlc: _hlc,
            deletedAt: Value(
              scenario == _FreshScenario.assetDeleted ? testNow : null,
            ),
          ),
        );
  }
}

Future<void> _insertAccount(
  AppDatabase db, {
  required String id,
  required AccountCategory type,
  required AccountSide side,
  required String owner,
  required String currency,
  required bool archived,
  required bool deleted,
}) => db
    .into(db.accounts)
    .insert(
      AccountsCompanion.insert(
        id: id,
        type: type,
        name: id,
        currency: currency,
        category: Value(side),
        archived: Value(archived),
        ownerUserId: owner,
        updatedAt: testNow,
        updatedByDevice: 'device-a',
        hlc: _hlc,
        deletedAt: Value(deleted ? testNow : null),
      ),
    );

final _hlc = Hlc(
  wallMillis: testNow.millisecondsSinceEpoch,
  counter: 0,
  nodeId: 'device-a',
);
