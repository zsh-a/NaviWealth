part of 'cost_basis_engine.dart';

List<Lot> _applySplit(
  CostBasisEngine engine,
  SplitAction action,
  Iterable<Lot> lots,
) {
  if (action.ratio.sign <= 0) {
    throw ArgumentError.value(
      action.ratio,
      'SplitAction.ratio',
      'must be positive',
    );
  }
  return lots.map((l) {
    if (l.assetId != action.assetId) return l;
    return l.copyWith(
      originalQuantity: l.originalQuantity * action.ratio,
      remainingQuantity: l.remainingQuantity * action.ratio,
      costPerUnit: (l.costPerUnit / action.ratio).toDecimal(
        scaleOnInfinitePrecision: engine._scale,
      ),
    );
  }).toList();
}

List<Lot> _applyStockDividend(
  CostBasisEngine engine,
  StockDividendAction action,
  Iterable<Lot> lots,
) {
  if (action.bonusRatio.sign < 0) {
    throw ArgumentError.value(
      action.bonusRatio,
      'StockDividendAction.bonusRatio',
      'must be non-negative',
    );
  }
  final factor = Decimal.one + action.bonusRatio;
  if (factor.sign <= 0) {
    throw ArgumentError.value(
      action.bonusRatio,
      'StockDividendAction.bonusRatio',
      'produced non-positive scale factor',
    );
  }
  return lots.map((l) {
    if (l.assetId != action.assetId) return l;
    return l.copyWith(
      originalQuantity: l.originalQuantity * factor,
      remainingQuantity: l.remainingQuantity * factor,
      costPerUnit: (l.costPerUnit / factor).toDecimal(
        scaleOnInfinitePrecision: engine._scale,
      ),
    );
  }).toList();
}

CashDividend? _applyCashDividend(
  CostBasisEngine engine,
  CashDividendAction action,
  Iterable<Lot> lots,
) {
  if (action.amountPerShare.sign < 0) {
    throw ArgumentError.value(
      action.amountPerShare,
      'CashDividendAction.amountPerShare',
      'must be non-negative',
    );
  }
  if (action.withholdingTax.sign < 0) {
    throw ArgumentError.value(
      action.withholdingTax,
      'CashDividendAction.withholdingTax',
      'must be non-negative',
    );
  }
  final shares = _eligibleShareCount(
    lots: lots,
    accountId: action.accountId,
    assetId: action.assetId,
    asOf: action.effectiveDate,
  );
  if (shares.sign <= 0) return null;
  final gross = shares * action.amountPerShare;
  if (action.withholdingTax > gross) {
    throw ArgumentError.value(
      action.withholdingTax,
      'CashDividendAction.withholdingTax',
      'cannot exceed gross dividend ($gross)',
    );
  }
  final net = gross - action.withholdingTax;
  return CashDividend(
    id: engine._idGenerator(),
    transactionId: action.transactionId,
    accountId: action.accountId,
    assetId: action.assetId,
    currency: action.currency,
    effectiveDate: action.effectiveDate,
    shareCount: shares,
    amountPerShare: action.amountPerShare,
    grossAmount: gross,
    withholdingTax: action.withholdingTax,
    netAmount: net,
    reinvested: false,
  );
}

DripResult _applyDrip(
  CostBasisEngine engine,
  DripAction action,
  Iterable<Lot> lots,
) {
  _requirePositive(action.amountPerShare, 'DripAction.amountPerShare');
  _requirePositive(action.pricePerUnit, 'DripAction.pricePerUnit');
  if (action.withholdingTax.sign < 0) {
    throw ArgumentError.value(
      action.withholdingTax,
      'DripAction.withholdingTax',
      'must be non-negative',
    );
  }
  if (action.fee.sign < 0) {
    throw ArgumentError.value(
      action.fee,
      'DripAction.fee',
      'must be non-negative',
    );
  }
  final lotsList = lots.toList();
  final shares = _eligibleShareCount(
    lots: lotsList,
    accountId: action.accountId,
    assetId: action.assetId,
    asOf: action.effectiveDate,
  );
  if (shares.sign <= 0) {
    throw ArgumentError.value(
      shares,
      'DripAction',
      'no eligible shares of ${action.assetId} held in '
          '${action.accountId} on ${action.effectiveDate}',
    );
  }
  final gross = shares * action.amountPerShare;
  if (action.withholdingTax > gross) {
    throw ArgumentError.value(
      action.withholdingTax,
      'DripAction.withholdingTax',
      'cannot exceed gross dividend ($gross)',
    );
  }
  final net = gross - action.withholdingTax;
  final cashAvailable = net - action.fee;
  if (cashAvailable.sign <= 0) {
    throw ArgumentError.value(
      action.fee,
      'DripAction.fee',
      'fee ($action.fee) exceeds net dividend ($net) — nothing to reinvest',
    );
  }
  final newLotQuantity = (cashAvailable / action.pricePerUnit).toDecimal(
    scaleOnInfinitePrecision: engine._scale,
  );
  if (newLotQuantity.sign <= 0) {
    throw ArgumentError.value(
      newLotQuantity,
      'DripAction',
      'reinvestment produced zero shares at scale ${engine._scale}',
    );
  }
  final totalCost = newLotQuantity * action.pricePerUnit + action.fee;
  final costPerUnit = (totalCost / newLotQuantity).toDecimal(
    scaleOnInfinitePrecision: engine._scale,
  );
  final newLot = Lot(
    id: engine._idGenerator(),
    openingTransactionId: action.transactionId,
    accountId: action.accountId,
    assetId: action.assetId,
    currency: action.currency,
    originalQuantity: newLotQuantity,
    remainingQuantity: newLotQuantity,
    costPerUnit: costPerUnit,
    openedAt: action.effectiveDate,
  );
  final dividend = CashDividend(
    id: engine._idGenerator(),
    transactionId: action.transactionId,
    accountId: action.accountId,
    assetId: action.assetId,
    currency: action.currency,
    effectiveDate: action.effectiveDate,
    shareCount: shares,
    amountPerShare: action.amountPerShare,
    grossAmount: gross,
    withholdingTax: action.withholdingTax,
    netAmount: net,
    reinvested: true,
  );
  return DripResult(
    cashDividend: dividend,
    newLot: newLot,
    updatedLots: [...lotsList, newLot],
  );
}

Lot _applyRightsIssue(CostBasisEngine engine, RightsIssueAction action) {
  _requirePositive(
    action.subscribedQuantity,
    'RightsIssueAction.subscribedQuantity',
  );
  final totalCost =
      action.subscribedQuantity * action.pricePerUnit + action.fee;
  final costPerUnit = (totalCost / action.subscribedQuantity).toDecimal(
    scaleOnInfinitePrecision: engine._scale,
  );
  return Lot(
    id: engine._idGenerator(),
    openingTransactionId: action.transactionId,
    accountId: action.accountId,
    assetId: action.assetId,
    currency: action.currency,
    originalQuantity: action.subscribedQuantity,
    remainingQuantity: action.subscribedQuantity,
    costPerUnit: costPerUnit,
    openedAt: action.effectiveDate,
  );
}
