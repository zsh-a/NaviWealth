import 'dart:convert';

import 'package:decimal/decimal.dart';

/// Typed view over the `metadataJson` blob stored on `assets` rows for
/// the no-market-data asset flavours.
///
/// The Drift schema already carries a free-form `metadata_json` column; we
/// keep that as the persistence shape (no extra columns / migrations) and
/// layer typed wrappers in the domain so feature code never deals with
/// stringly-typed lookups.
///
/// Sync semantics: changes to deposit/wealth-product specifics show up in
/// the `fields_diff` payload as a single `metadata_json` field. That gives
/// us row-level (rather than column-level) LWW *within* the metadata blob,
/// which is acceptable for v1 — the inner fields rarely race because they
/// only mutate when a user edits the holding.
sealed class ManualAssetMetadata {
  const ManualAssetMetadata({required this.accountId});

  /// Account that "owns" this holding. Embedded here rather than added as
  /// a new column so manual-asset metadata stays feature-local while the
  /// ledger carries the accounting postings.
  final String accountId;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static ManualAssetMetadata? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final raw = jsonDecode(json);
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k as String, v));
    final kind = map['kind'];
    return switch (kind) {
      'cash' => CashMetadata.fromJson(map),
      'deposit' => DepositMetadata.fromJson(map),
      'wealth_product' => WealthProductMetadata.fromJson(map),
      _ => null,
    };
  }
}

/// 现金 — a balance in a specific currency held within a single account.
class CashMetadata extends ManualAssetMetadata {
  const CashMetadata({required super.accountId});

  @override
  Map<String, Object?> toJson() => {'kind': 'cash', 'account_id': accountId};

  factory CashMetadata.fromJson(Map<String, Object?> j) =>
      CashMetadata(accountId: j['account_id']! as String);

  @override
  bool operator ==(Object other) =>
      other is CashMetadata && other.accountId == accountId;

  @override
  int get hashCode => Object.hash('cash', accountId);
}

/// Bank deposit (term or demand). The flavour itself is encoded in the
/// owning `Asset.type` (`bankDepositTerm` vs. `bankDepositDemand`); this
/// struct just carries the numbers.
class DepositMetadata extends ManualAssetMetadata {
  const DepositMetadata({
    required super.accountId,
    required this.principal,
    required this.interestRate,
    this.startDate,
    this.maturityDate,
    this.autoRenew = false,
  });

  /// Initial deposit amount in the asset's currency.
  final Decimal principal;

  /// Annualised rate as a fraction (`0.0325` = 3.25%). We store rates as a
  /// fraction — same convention as FX rates and expected returns elsewhere
  /// in the model — because mixing percent/fraction across fields is the
  /// kind of bug that takes a quarter to notice.
  final Decimal interestRate;

  /// 起息日 — present for term deposits; demand deposits leave it null
  /// because interest accrues from the moment funds land.
  final DateTime? startDate;

  /// 到期日 — null for demand deposits.
  final DateTime? maturityDate;

  /// 自动续存 (term deposits only). Informational; we don't auto-create a
  /// successor deposit on the maturity date — that's a future task.
  final bool autoRenew;

  DepositMetadata copyWith({
    String? accountId,
    Decimal? principal,
    Decimal? interestRate,
    DateTime? startDate,
    DateTime? maturityDate,
    bool? autoRenew,
  }) => DepositMetadata(
    accountId: accountId ?? this.accountId,
    principal: principal ?? this.principal,
    interestRate: interestRate ?? this.interestRate,
    startDate: startDate ?? this.startDate,
    maturityDate: maturityDate ?? this.maturityDate,
    autoRenew: autoRenew ?? this.autoRenew,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'deposit',
    'account_id': accountId,
    'principal': principal.toString(),
    'interest_rate': interestRate.toString(),
    if (startDate != null) 'start_date': startDate!.toUtc().toIso8601String(),
    if (maturityDate != null)
      'maturity_date': maturityDate!.toUtc().toIso8601String(),
    'auto_renew': autoRenew,
  };

  factory DepositMetadata.fromJson(Map<String, Object?> j) => DepositMetadata(
    accountId: j['account_id']! as String,
    principal: Decimal.parse(j['principal']! as String),
    interestRate: Decimal.parse(j['interest_rate']! as String),
    startDate: _parseDate(j['start_date']),
    maturityDate: _parseDate(j['maturity_date']),
    autoRenew: (j['auto_renew'] as bool?) ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is DepositMetadata &&
      other.accountId == accountId &&
      other.principal == principal &&
      other.interestRate == interestRate &&
      other.startDate == startDate &&
      other.maturityDate == maturityDate &&
      other.autoRenew == autoRenew;

  @override
  int get hashCode => Object.hash(
    'deposit',
    accountId,
    principal,
    interestRate,
    startDate,
    maturityDate,
    autoRenew,
  );
}

/// 理财产品 — manually-managed structured product / fund-of-funds where
/// the user types in the current valuation themselves (no market feed).
class WealthProductMetadata extends ManualAssetMetadata {
  const WealthProductMetadata({
    required super.accountId,
    required this.principal,
    required this.expectedAnnualReturn,
    this.startDate,
    this.maturityDate,
    this.issuer,
    this.productCode,
  });

  /// 认购金额, in the asset's currency.
  final Decimal principal;

  /// 预期年化收益率 — fraction, same convention as [DepositMetadata.interestRate].
  final Decimal expectedAnnualReturn;

  /// 起息日.
  final DateTime? startDate;

  /// 到期日 — open-ended products leave this null.
  final DateTime? maturityDate;

  /// 发行机构 (e.g. "招商银行"). Optional.
  final String? issuer;

  /// 产品代码 — bank-internal SKU. Optional but useful in lists.
  final String? productCode;

  WealthProductMetadata copyWith({
    String? accountId,
    Decimal? principal,
    Decimal? expectedAnnualReturn,
    DateTime? startDate,
    DateTime? maturityDate,
    String? issuer,
    String? productCode,
  }) => WealthProductMetadata(
    accountId: accountId ?? this.accountId,
    principal: principal ?? this.principal,
    expectedAnnualReturn: expectedAnnualReturn ?? this.expectedAnnualReturn,
    startDate: startDate ?? this.startDate,
    maturityDate: maturityDate ?? this.maturityDate,
    issuer: issuer ?? this.issuer,
    productCode: productCode ?? this.productCode,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'wealth_product',
    'account_id': accountId,
    'principal': principal.toString(),
    'expected_annual_return': expectedAnnualReturn.toString(),
    if (startDate != null) 'start_date': startDate!.toUtc().toIso8601String(),
    if (maturityDate != null)
      'maturity_date': maturityDate!.toUtc().toIso8601String(),
    if (issuer != null) 'issuer': issuer,
    if (productCode != null) 'product_code': productCode,
  };

  factory WealthProductMetadata.fromJson(Map<String, Object?> j) =>
      WealthProductMetadata(
        accountId: j['account_id']! as String,
        principal: Decimal.parse(j['principal']! as String),
        expectedAnnualReturn: Decimal.parse(
          j['expected_annual_return']! as String,
        ),
        startDate: _parseDate(j['start_date']),
        maturityDate: _parseDate(j['maturity_date']),
        issuer: j['issuer'] as String?,
        productCode: j['product_code'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is WealthProductMetadata &&
      other.accountId == accountId &&
      other.principal == principal &&
      other.expectedAnnualReturn == expectedAnnualReturn &&
      other.startDate == startDate &&
      other.maturityDate == maturityDate &&
      other.issuer == issuer &&
      other.productCode == productCode;

  @override
  int get hashCode => Object.hash(
    'wealth_product',
    accountId,
    principal,
    expectedAnnualReturn,
    startDate,
    maturityDate,
    issuer,
    productCode,
  );
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String) return null;
  return DateTime.parse(raw);
}
