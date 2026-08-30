import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_mutation_receipt.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/features/finance/domain/models/price_observation.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';

import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';

abstract final class RebalancePlanCodec {
  static String encode(RebalancePlan plan) =>
      _encodeEnvelope(kind: 'rebalancePlan', payload: _planToJson(plan));

  static RebalancePlan decode(String raw) => _guard('rebalance plan', () {
    return _planFromJson(_decodeEnvelope(raw, kind: 'rebalancePlan'));
  });
}

abstract final class RebalanceSuggestionCodec {
  static String encode(SuggestedTrade suggestion) => _encodeEnvelope(
    kind: 'rebalanceSuggestion',
    payload: _suggestionToJson(suggestion),
  );

  static SuggestedTrade decode(String raw) => _guard(
    'rebalance suggestion',
    () =>
        _suggestionFromJson(_decodeEnvelope(raw, kind: 'rebalanceSuggestion')),
  );
}

abstract final class RebalanceExecutionRequestCodec {
  static String encode(RebalanceExecutionRequest request) {
    _validateRequest(request);
    return _encodeEnvelope(
      kind: 'rebalanceExecutionRequest',
      payload: {
        'transactionId': request.transactionId,
        'account': _accountToJson(request.account),
        'cashAccount': request.cashAccount == null
            ? null
            : _accountToJson(request.cashAccount!),
        'asset': _assetToJson(request.asset),
        'type': request.type.name,
        'quantity': _decimalToString(request.quantity),
        'price': _nullableDecimalToString(request.price),
        'currency': request.currency,
        'tradeDate': _dateToString(request.tradeDate),
        'fee': _nullableDecimalToString(request.fee),
        'tax': _nullableDecimalToString(request.tax),
        'note': request.note,
      },
    );
  }

  static RebalanceExecutionRequest decode(String raw) =>
      _guard('rebalance execution request', () {
        final json = _decodeEnvelope(raw, kind: 'rebalanceExecutionRequest');
        _expectExactKeys(json, const {
          'transactionId',
          'account',
          'cashAccount',
          'asset',
          'type',
          'quantity',
          'price',
          'currency',
          'tradeDate',
          'fee',
          'tax',
          'note',
        }, 'rebalance execution request');
        final request = RebalanceExecutionRequest(
          transactionId: _string(json, 'transactionId'),
          account: _accountFromJson(_map(json, 'account')),
          cashAccount: _nullableMap(json, 'cashAccount') == null
              ? null
              : _accountFromJson(_nullableMap(json, 'cashAccount')!),
          asset: _assetFromJson(_map(json, 'asset')),
          type: _enumValue(TradeType.values, _string(json, 'type'), 'type'),
          quantity: _decimal(json, 'quantity'),
          price: _nullableDecimal(json, 'price'),
          currency: _string(json, 'currency'),
          tradeDate: _date(json, 'tradeDate'),
          fee: _nullableDecimal(json, 'fee'),
          tax: _nullableDecimal(json, 'tax'),
          note: _nullableString(json, 'note'),
        );
        _validateRequest(request);
        return request;
      });
}

abstract final class TradeMutationReceiptCodec {
  static String encode(TradeMutationReceipt receipt) {
    _validateReceipt(receipt);
    return _encodeEnvelope(
      kind: 'tradeMutationReceipt',
      payload: {
        'transactionId': receipt.transactionId,
        'assetAfter': _assetToJson(receipt.assetAfter),
        'journal': _journalReceiptToJson(receipt.journal),
        'price': receipt.price == null
            ? null
            : _priceReceiptToJson(receipt.price!),
      },
    );
  }

  static TradeMutationReceipt decode(String raw) =>
      _guard('trade mutation receipt', () {
        final json = _decodeEnvelope(raw, kind: 'tradeMutationReceipt');
        _expectExactKeys(json, const {
          'transactionId',
          'assetAfter',
          'journal',
          'price',
        }, 'trade mutation receipt');
        final price = _nullableMap(json, 'price');
        final receipt = TradeMutationReceipt(
          transactionId: _string(json, 'transactionId'),
          assetAfter: _assetFromJson(_map(json, 'assetAfter')),
          journal: _journalReceiptFromJson(_map(json, 'journal')),
          price: price == null ? null : _priceReceiptFromJson(price),
        );
        _validateReceipt(receipt);
        return receipt;
      });
}

abstract final class RebalancePlanFingerprint {
  static String compute(RebalancePlan plan) {
    final canonical = RebalancePlanCodec.encode(plan);
    return 'rebalance-plan/v1:${sha256.convert(utf8.encode(canonical))}';
  }
}

Map<String, Object?> _planToJson(RebalancePlan plan) {
  final drifts = [...plan.drifts]..sort(_compareDrifts);
  final trades = [...plan.trades]..sort(_compareSuggestions);
  return {
    'target': {
      'categories': {
        for (final entry in plan.target.weights.entries)
          entry.key.name: _doubleToString(entry.value),
      },
      'assets': {
        for (final entry in plan.target.assetTargets.entries)
          entry.key: {
            'assetId': entry.value.assetId,
            'label': entry.value.label,
            'category': entry.value.category.name,
            'weight': _doubleToString(entry.value.weight),
          },
      },
    },
    'actualWeights': {
      for (final entry in plan.actualWeights.entries)
        entry.key.name: _doubleToString(entry.value),
    },
    'drifts': [for (final drift in drifts) _driftToJson(drift)],
    'trades': [for (final trade in trades) _suggestionToJson(trade)],
    'estimatedFees': _moneyToJson(plan.estimatedFees),
    'estimatedTaxes': _moneyToJson(plan.estimatedTaxes),
    'driftBeforePct': _doubleToString(plan.driftBeforePct),
    'driftAfterPct': _doubleToString(plan.driftAfterPct),
    'totalAssets': _moneyToJson(plan.totalAssets),
  };
}

RebalancePlan _planFromJson(Map<String, Object?> json) {
  _expectExactKeys(json, const {
    'target',
    'actualWeights',
    'drifts',
    'trades',
    'estimatedFees',
    'estimatedTaxes',
    'driftBeforePct',
    'driftAfterPct',
    'totalAssets',
  }, 'rebalance plan');
  final targetJson = _map(json, 'target');
  _expectExactKeys(targetJson, const {
    'categories',
    'assets',
  }, 'rebalance plan target');
  final categoryJson = _map(targetJson, 'categories');
  final assetJson = _map(targetJson, 'assets');
  final targetWeights = <AssetCategory, double>{};
  for (final entry in categoryJson.entries) {
    final category = _enumValue(
      AssetCategory.values,
      entry.key,
      'target.categories.${entry.key}',
    );
    targetWeights[category] = _decimalValue(
      entry.value,
      'target.categories.${entry.key}',
    ).toDouble();
  }
  final assetTargets = <String, AssetTargetAllocation>{};
  for (final entry in assetJson.entries) {
    final value = _asMap(entry.value, 'target.assets.${entry.key}');
    _expectExactKeys(value, const {
      'assetId',
      'label',
      'category',
      'weight',
    }, 'target asset ${entry.key}');
    final assetId = _string(value, 'assetId');
    if (assetId != entry.key) {
      throw RebalanceExecutionCodecError(
        'Asset target key ${entry.key} does not match assetId $assetId.',
      );
    }
    assetTargets[assetId] = AssetTargetAllocation(
      assetId: assetId,
      label: _string(value, 'label'),
      category: _enumValue(
        AssetCategory.values,
        _string(value, 'category'),
        'category',
      ),
      weight: _decimal(value, 'weight').toDouble(),
    );
  }
  final actualJson = _map(json, 'actualWeights');
  final actualWeights = <AssetCategory, double>{};
  for (final entry in actualJson.entries) {
    actualWeights[_enumValue(
      AssetCategory.values,
      entry.key,
      'actualWeights key',
    )] = _decimalValue(
      entry.value,
      'actualWeights.${entry.key}',
    ).toDouble();
  }
  final drifts = _list(json, 'drifts')
      .map((value) => _driftFromJson(_asMap(value, 'drifts item')))
      .toList(growable: false);
  final trades = _list(json, 'trades')
      .map((value) => _suggestionFromJson(_asMap(value, 'trades item')))
      .toList(growable: false);
  return RebalancePlan(
    target: TargetAllocation(
      weights: targetWeights,
      assetTargets: assetTargets,
    ),
    actualWeights: actualWeights,
    drifts: drifts,
    trades: trades,
    estimatedFees: _moneyFromJson(_map(json, 'estimatedFees')),
    estimatedTaxes: _moneyFromJson(_map(json, 'estimatedTaxes')),
    driftBeforePct: _decimal(json, 'driftBeforePct').toDouble(),
    driftAfterPct: _decimal(json, 'driftAfterPct').toDouble(),
    totalAssets: _moneyFromJson(_map(json, 'totalAssets')),
  );
}

Map<String, Object?> _driftToJson(Drift drift) => {
  'category': drift.category.name,
  'assetId': drift.assetId,
  'assetLabel': drift.assetLabel,
  'actualWeight': _doubleToString(drift.actualWeight),
  'targetWeight': _doubleToString(drift.targetWeight),
  'severity': drift.severity.name,
};

Drift _driftFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {
    'category',
    'assetId',
    'assetLabel',
    'actualWeight',
    'targetWeight',
    'severity',
  },
  'rebalance drift',
  () => Drift(
    category: _enumValue(
      AssetCategory.values,
      _string(json, 'category'),
      'category',
    ),
    assetId: _nullableString(json, 'assetId'),
    assetLabel: _nullableString(json, 'assetLabel'),
    actualWeight: _decimal(json, 'actualWeight').toDouble(),
    targetWeight: _decimal(json, 'targetWeight').toDouble(),
    severity: _enumValue(
      DriftSeverity.values,
      _string(json, 'severity'),
      'severity',
    ),
  ),
);

Map<String, Object?> _suggestionToJson(SuggestedTrade suggestion) => {
  'category': suggestion.category.name,
  'assetId': suggestion.assetId,
  'assetLabel': suggestion.assetLabel,
  'direction': suggestion.direction.name,
  'amount': _moneyToJson(suggestion.amount),
  'description': suggestion.description,
};

SuggestedTrade _suggestionFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {
    'category',
    'assetId',
    'assetLabel',
    'direction',
    'amount',
    'description',
  },
  'rebalance suggestion',
  () => SuggestedTrade(
    category: _enumValue(
      AssetCategory.values,
      _string(json, 'category'),
      'category',
    ),
    assetId: _nullableString(json, 'assetId'),
    assetLabel: _nullableString(json, 'assetLabel'),
    direction: _enumValue(
      TradeDirection.values,
      _string(json, 'direction'),
      'direction',
    ),
    amount: _moneyFromJson(_map(json, 'amount')),
    description: _nullableString(json, 'description'),
  ),
);

Map<String, Object?> _moneyToJson(Money money) => {
  'amount': _decimalToString(money.amount),
  'currency': money.currency,
};

Money _moneyFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {'amount', 'currency'},
  'money',
  () => Money(_decimal(json, 'amount'), _string(json, 'currency')),
);

Map<String, Object?> _accountToJson(Account account) => {
  'id': account.id,
  'type': account.type.name,
  'name': account.name,
  'currency': account.currency,
  'institution': account.institution,
  'accountNumber': account.accountNumber,
  'note': account.note,
  'archived': account.archived,
  'category': account.category.name,
  'parentId': account.parentId,
  'icon': account.icon,
  'color': account.color,
  'sync': _syncToJson(account.sync),
};

Account _accountFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {
    'id',
    'type',
    'name',
    'currency',
    'institution',
    'accountNumber',
    'note',
    'archived',
    'category',
    'parentId',
    'icon',
    'color',
    'sync',
  },
  'account',
  () => Account(
    id: _string(json, 'id'),
    type: _enumValue(AccountCategory.values, _string(json, 'type'), 'type'),
    name: _string(json, 'name'),
    currency: _string(json, 'currency'),
    institution: _nullableString(json, 'institution'),
    accountNumber: _nullableString(json, 'accountNumber'),
    note: _nullableString(json, 'note'),
    archived: _bool(json, 'archived'),
    category: _enumValue(
      AccountSide.values,
      _string(json, 'category'),
      'category',
    ),
    parentId: _nullableString(json, 'parentId'),
    icon: _nullableString(json, 'icon'),
    color: _nullableString(json, 'color'),
    sync: _syncFromJson(_map(json, 'sync')),
  ),
);

Map<String, Object?> _assetToJson(Asset asset) => {
  'id': asset.id,
  'type': asset.type.name,
  'symbol': asset.symbol,
  'currency': asset.currency,
  'name': asset.name,
  'market': asset.market,
  'industry': asset.industry,
  'region': asset.region,
  'isin': asset.isin,
  'logoUrl': asset.logoUrl,
  'metadataJson': asset.metadataJson,
  'sync': _syncToJson(asset.sync),
};

Asset _assetFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {
    'id',
    'type',
    'symbol',
    'currency',
    'name',
    'market',
    'industry',
    'region',
    'isin',
    'logoUrl',
    'metadataJson',
    'sync',
  },
  'asset',
  () => Asset(
    id: _string(json, 'id'),
    type: _enumValue(AssetType.values, _string(json, 'type'), 'type'),
    symbol: _string(json, 'symbol'),
    currency: _string(json, 'currency'),
    name: _nullableString(json, 'name'),
    market: _nullableString(json, 'market'),
    industry: _nullableString(json, 'industry'),
    region: _nullableString(json, 'region'),
    isin: _nullableString(json, 'isin'),
    logoUrl: _nullableString(json, 'logoUrl'),
    metadataJson: _nullableString(json, 'metadataJson'),
    sync: _syncFromJson(_map(json, 'sync')),
  ),
);

Map<String, Object?> _syncToJson(SyncMeta sync) => {
  'ownerUserId': sync.ownerUserId,
  'updatedAt': _dateToString(sync.updatedAt),
  'updatedByDevice': sync.updatedByDevice,
  'hlc': sync.hlc.toString(),
  'deletedAt': sync.deletedAt == null ? null : _dateToString(sync.deletedAt!),
};

SyncMeta _syncFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {'ownerUserId', 'updatedAt', 'updatedByDevice', 'hlc', 'deletedAt'},
  'sync metadata',
  () => SyncMeta(
    ownerUserId: _string(json, 'ownerUserId'),
    updatedAt: _date(json, 'updatedAt'),
    updatedByDevice: _string(json, 'updatedByDevice'),
    hlc: _hlc(json, 'hlc'),
    deletedAt: _nullableDate(json, 'deletedAt'),
  ),
);

Map<String, Object?> _journalReceiptToJson(JournalMutationReceipt receipt) => {
  'before': receipt.before == null
      ? null
      : _journalWithPostingsToJson(receipt.before!),
  'after': _journalWithPostingsToJson(receipt.after),
};

JournalMutationReceipt _journalReceiptFromJson(Map<String, Object?> json) {
  _expectExactKeys(json, const {'before', 'after'}, 'journal receipt');
  final before = _nullableMap(json, 'before');
  return JournalMutationReceipt(
    before: before == null ? null : _journalWithPostingsFromJson(before),
    after: _journalWithPostingsFromJson(_map(json, 'after')),
  );
}

Map<String, Object?> _journalWithPostingsToJson(
  JournalEntryWithPostings value,
) => {
  'entry': _journalEntryToJson(value.entry),
  'postings': [for (final posting in value.postings) _postingToJson(posting)],
};

JournalEntryWithPostings _journalWithPostingsFromJson(
  Map<String, Object?> json,
) => _strictObject(
  json,
  const {'entry', 'postings'},
  'journal with postings',
  () => JournalEntryWithPostings(
    entry: _journalEntryFromJson(_map(json, 'entry')),
    postings: _list(json, 'postings')
        .map((value) => _postingFromJson(_asMap(value, 'postings item')))
        .toList(growable: false),
  ),
);

Map<String, Object?> _journalEntryToJson(JournalEntry entry) => {
  'id': entry.id,
  'date': _dateToString(entry.date),
  'settledOn': entry.settledOn == null ? null : _dateToString(entry.settledOn!),
  'narration': entry.narration,
  'payee': entry.payee,
  'tagIds': entry.tagIds,
  'flag': entry.flag.name,
  'sync': _syncToJson(entry.sync),
};

JournalEntry _journalEntryFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {
    'id',
    'date',
    'settledOn',
    'narration',
    'payee',
    'tagIds',
    'flag',
    'sync',
  },
  'journal entry',
  () => JournalEntry(
    id: _string(json, 'id'),
    date: _date(json, 'date'),
    settledOn: _nullableDate(json, 'settledOn'),
    narration: _string(json, 'narration'),
    payee: _nullableString(json, 'payee'),
    tagIds: _stringList(json, 'tagIds'),
    flag: _enumValue(EntryFlag.values, _string(json, 'flag'), 'flag'),
    sync: _syncFromJson(_map(json, 'sync')),
  ),
);

Map<String, Object?> _postingToJson(Posting posting) => {
  'id': posting.id,
  'journalEntryId': posting.journalEntryId,
  'position': posting.position,
  'accountId': posting.accountId,
  'units': _decimalToString(posting.units),
  'unit': posting.unit,
  'cost': posting.cost == null ? null : _costToJson(posting.cost!),
  'price': posting.price == null ? null : _priceToJson(posting.price!),
  'sync': _syncToJson(posting.sync),
};

Posting _postingFromJson(Map<String, Object?> json) {
  _expectExactKeys(json, const {
    'id',
    'journalEntryId',
    'position',
    'accountId',
    'units',
    'unit',
    'cost',
    'price',
    'sync',
  }, 'posting');
  final cost = _nullableMap(json, 'cost');
  final price = _nullableMap(json, 'price');
  return Posting(
    id: _string(json, 'id'),
    journalEntryId: _string(json, 'journalEntryId'),
    position: _int(json, 'position'),
    accountId: _string(json, 'accountId'),
    units: _decimal(json, 'units'),
    unit: _string(json, 'unit'),
    cost: cost == null ? null : _costFromJson(cost),
    price: price == null ? null : _priceFromJson(price),
    sync: _syncFromJson(_map(json, 'sync')),
  );
}

Map<String, Object?> _costToJson(Cost cost) => {
  'perUnit': _decimalToString(cost.perUnit),
  'currency': cost.currency,
  'lotId': cost.lotId,
  'acquiredOn': cost.acquiredOn == null
      ? null
      : _dateToString(cost.acquiredOn!),
};

Cost _costFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {'perUnit', 'currency', 'lotId', 'acquiredOn'},
  'posting cost',
  () => Cost(
    perUnit: _decimal(json, 'perUnit'),
    currency: _string(json, 'currency'),
    lotId: _nullableString(json, 'lotId'),
    acquiredOn: _nullableDate(json, 'acquiredOn'),
  ),
);

Map<String, Object?> _priceToJson(Price price) => {
  'perUnit': _decimalToString(price.perUnit),
  'currency': price.currency,
};

Price _priceFromJson(Map<String, Object?> json) => _strictObject(
  json,
  const {'perUnit', 'currency'},
  'posting price',
  () => Price(
    perUnit: _decimal(json, 'perUnit'),
    currency: _string(json, 'currency'),
  ),
);

Map<String, Object?> _priceReceiptToJson(PriceMutationReceipt receipt) => {
  'before': receipt.before == null
      ? null
      : _priceObservationToJson(receipt.before!),
  'after': _priceObservationToJson(receipt.after),
};

PriceMutationReceipt _priceReceiptFromJson(Map<String, Object?> json) {
  _expectExactKeys(json, const {'before', 'after'}, 'price receipt');
  final before = _nullableMap(json, 'before');
  return PriceMutationReceipt(
    before: before == null ? null : _priceObservationFromJson(before),
    after: _priceObservationFromJson(_map(json, 'after')),
  );
}

Map<String, Object?> _priceObservationToJson(PriceObservation observation) => {
  'id': observation.id,
  'unit': observation.unit,
  'quoteCurrency': observation.quoteCurrency,
  'observedOn': _dateToString(observation.observedOn),
  'perUnit': _decimalToString(observation.perUnit),
  'source': observation.source,
  'sync': _syncToJson(observation.sync),
};

PriceObservation _priceObservationFromJson(Map<String, Object?> json) =>
    _strictObject(
      json,
      const {
        'id',
        'unit',
        'quoteCurrency',
        'observedOn',
        'perUnit',
        'source',
        'sync',
      },
      'price observation',
      () => PriceObservation(
        id: _string(json, 'id'),
        unit: _string(json, 'unit'),
        quoteCurrency: _string(json, 'quoteCurrency'),
        observedOn: _date(json, 'observedOn'),
        perUnit: _decimal(json, 'perUnit'),
        source: _string(json, 'source'),
        sync: _syncFromJson(_map(json, 'sync')),
      ),
    );

void _validateRequest(RebalanceExecutionRequest request) {
  if (request.transactionId.isEmpty ||
      request.account.id.isEmpty ||
      request.asset.id.isEmpty) {
    throw const RebalanceExecutionCodecError(
      'Request transaction, account, and asset ids must not be empty.',
    );
  }
  final owner = request.account.sync.ownerUserId;
  if (owner.isEmpty ||
      request.asset.sync.ownerUserId != owner ||
      (request.cashAccount != null &&
          request.cashAccount!.sync.ownerUserId != owner)) {
    throw const RebalanceExecutionCodecError(
      'Request account and asset snapshots must share one owner.',
    );
  }
}

void _validateReceipt(TradeMutationReceipt receipt) {
  final transactionId = receipt.transactionId;
  final owner = receipt.assetAfter.sync.ownerUserId;
  if (transactionId.isEmpty || owner.isEmpty) {
    throw const RebalanceExecutionCodecError(
      'Receipt transaction id and owner must not be empty.',
    );
  }

  void validateJournal(JournalEntryWithPostings value) {
    if (value.entry.id != transactionId ||
        value.entry.sync.ownerUserId != owner ||
        value.postings.any(
          (posting) =>
              posting.journalEntryId != value.entry.id ||
              posting.sync.ownerUserId != owner,
        )) {
      throw const RebalanceExecutionCodecError(
        'Receipt journal rows must match the transaction and owner.',
      );
    }
  }

  final beforeJournal = receipt.journal.before;
  if (beforeJournal != null) validateJournal(beforeJournal);
  validateJournal(receipt.journal.after);
  final price = receipt.price;
  if (price == null) return;
  final beforePrice = price.before;
  if (price.after.id != transactionId ||
      price.after.unit != receipt.assetAfter.id ||
      price.after.sync.ownerUserId != owner ||
      (beforePrice != null &&
          (beforePrice.id != transactionId ||
              beforePrice.sync.ownerUserId != owner))) {
    throw const RebalanceExecutionCodecError(
      'Receipt price rows must match the transaction, asset, and owner.',
    );
  }
}

int _compareDrifts(Drift left, Drift right) {
  var value = left.category.index.compareTo(right.category.index);
  if (value != 0) return value;
  value = (left.assetId ?? '').compareTo(right.assetId ?? '');
  if (value != 0) return value;
  value = (left.assetLabel ?? '').compareTo(right.assetLabel ?? '');
  if (value != 0) return value;
  value = _doubleToString(left.actualWeight)
      .compareTo(_doubleToString(right.actualWeight));
  if (value != 0) return value;
  value = _doubleToString(left.targetWeight)
      .compareTo(_doubleToString(right.targetWeight));
  if (value != 0) return value;
  return left.severity.index.compareTo(right.severity.index);
}

int _compareSuggestions(SuggestedTrade left, SuggestedTrade right) {
  final leftDirection = left.isSell ? 0 : 1;
  final rightDirection = right.isSell ? 0 : 1;
  var value = leftDirection.compareTo(rightDirection);
  if (value != 0) return value;
  value = left.category.index.compareTo(right.category.index);
  if (value != 0) return value;
  value = (left.assetId ?? '').compareTo(right.assetId ?? '');
  if (value != 0) return value;
  value = (left.assetLabel ?? '').compareTo(right.assetLabel ?? '');
  if (value != 0) return value;
  value = left.amount.currency.compareTo(right.amount.currency);
  if (value != 0) return value;
  value = left.amount.amount.compareTo(right.amount.amount);
  if (value != 0) return value;
  return (left.description ?? '').compareTo(right.description ?? '');
}

String _encodeEnvelope({
  required String kind,
  required Map<String, Object?> payload,
}) => jsonEncode(_sortJson({'kind': kind, 'version': 1, 'payload': payload}));

Map<String, Object?> _decodeEnvelope(String raw, {required String kind}) {
  final decoded = jsonDecode(raw);
  final envelope = _asMap(decoded, 'envelope');
  _expectExactKeys(envelope, const {
    'kind',
    'version',
    'payload',
  }, '$kind envelope');
  if (_string(envelope, 'kind') != kind) {
    throw RebalanceExecutionCodecError('Expected codec kind $kind.');
  }
  final version = _int(envelope, 'version');
  if (version != 1) {
    throw RebalanceExecutionCodecError('Unsupported $kind version $version.');
  }
  return _map(envelope, 'payload');
}

Object? _sortJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortJson(value[key]),
    };
  }
  if (value is List) return [for (final item in value) _sortJson(item)];
  return value;
}

T _guard<T>(String label, T Function() decode) {
  try {
    return decode();
  } on RebalanceExecutionCodecError {
    rethrow;
  } catch (error) {
    throw RebalanceExecutionCodecError('Invalid $label: $error');
  }
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw RebalanceExecutionCodecError('$field must be an object.');
  }
  return value;
}

void _expectExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
) {
  final actual = json.keys.toSet();
  if (actual.length == expected.length && actual.containsAll(expected)) return;
  final missing = expected.difference(actual).toList()..sort();
  final unknown = actual.difference(expected).toList()..sort();
  throw RebalanceExecutionCodecError(
    '$context has invalid fields; missing=$missing unknown=$unknown.',
  );
}

T _strictObject<T>(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
  T Function() decode,
) {
  _expectExactKeys(json, expected, context);
  return decode();
}

Map<String, Object?> _map(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw RebalanceExecutionCodecError('Missing field $field.');
  }
  return _asMap(json[field], field);
}

Map<String, Object?>? _nullableMap(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw RebalanceExecutionCodecError('Missing field $field.');
  }
  final value = json[field];
  return value == null ? null : _asMap(value, field);
}

List<Object?> _list(Map<String, Object?> json, String field) {
  if (!json.containsKey(field) || json[field] is! List) {
    throw RebalanceExecutionCodecError('$field must be a list.');
  }
  return (json[field]! as List).cast<Object?>();
}

String _string(Map<String, Object?> json, String field) {
  if (!json.containsKey(field) || json[field] is! String) {
    throw RebalanceExecutionCodecError('$field must be a string.');
  }
  return json[field]! as String;
}

String? _nullableString(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw RebalanceExecutionCodecError('Missing field $field.');
  }
  final value = json[field];
  if (value != null && value is! String) {
    throw RebalanceExecutionCodecError('$field must be a string or null.');
  }
  return value as String?;
}

bool _bool(Map<String, Object?> json, String field) {
  if (!json.containsKey(field) || json[field] is! bool) {
    throw RebalanceExecutionCodecError('$field must be a bool.');
  }
  return json[field]! as bool;
}

int _int(Map<String, Object?> json, String field) {
  if (!json.containsKey(field) || json[field] is! int) {
    throw RebalanceExecutionCodecError('$field must be an int.');
  }
  return json[field]! as int;
}

List<String> _stringList(Map<String, Object?> json, String field) {
  final values = _list(json, field);
  if (values.any((value) => value is! String)) {
    throw RebalanceExecutionCodecError('$field must contain only strings.');
  }
  return values.cast<String>();
}

Decimal _decimal(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw RebalanceExecutionCodecError('Missing field $field.');
  }
  return _decimalValue(json[field], field);
}

Decimal _decimalValue(Object? value, String field) {
  if (value is! String) {
    throw RebalanceExecutionCodecError('$field must be a Decimal string.');
  }
  try {
    return Decimal.parse(value);
  } catch (_) {
    throw RebalanceExecutionCodecError('$field is not a valid Decimal.');
  }
}

Decimal? _nullableDecimal(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw RebalanceExecutionCodecError('Missing field $field.');
  }
  final value = json[field];
  return value == null ? null : _decimalValue(value, field);
}

String _decimalToString(Decimal value) => value.toString();

String? _nullableDecimalToString(Decimal? value) =>
    value == null ? null : _decimalToString(value);

String _doubleToString(double value) =>
    _guard('finite Decimal', () => Decimal.parse(value.toString()).toString());

DateTime _date(Map<String, Object?> json, String field) {
  final raw = _string(json, field);
  return _dateValue(raw, field);
}

DateTime? _nullableDate(Map<String, Object?> json, String field) {
  final raw = _nullableString(json, field);
  return raw == null ? null : _dateValue(raw, field);
}

DateTime _dateValue(String raw, String field) {
  if (!raw.endsWith('Z')) {
    throw RebalanceExecutionCodecError('$field must be a UTC ISO timestamp.');
  }
  final value = DateTime.tryParse(raw);
  if (value == null || !value.isUtc) {
    throw RebalanceExecutionCodecError('$field must be a UTC ISO timestamp.');
  }
  return value;
}

String _dateToString(DateTime value) {
  if (!value.isUtc) {
    throw const RebalanceExecutionCodecError(
      'DateTime values must already be UTC.',
    );
  }
  return value.toIso8601String();
}

Hlc _hlc(Map<String, Object?> json, String field) {
  final raw = _string(json, field);
  try {
    return Hlc.parse(raw);
  } catch (_) {
    throw RebalanceExecutionCodecError('$field is not a valid HLC.');
  }
}

T _enumValue<T extends Enum>(List<T> values, String raw, String field) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw RebalanceExecutionCodecError('$field has unknown enum value $raw.');
}
