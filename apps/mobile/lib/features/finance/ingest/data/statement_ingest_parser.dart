/// Provider-specific statement parser entry point.
///
/// The generic CSV parser intentionally stays broad and conservative. This
/// wrapper adds deterministic provider detection and small normalisations for
/// exports with known semantics, without introducing LLM guessing on the save
/// path.
library;

import '../domain/ingest_models.dart';
import 'bank_ingest_parser.dart';
import 'broker_ingest_parser.dart';
import 'csv_ingest_parser.dart';

enum StatementProvider { auto, generic, alipay, wechatPay, bank, broker }

StatementProvider detectStatementProvider(String raw) {
  final compact = raw.replaceAll(RegExp(r'\s+'), '');
  if (compact.contains('支付宝交易记录明细') ||
      compact.contains('交易号,商家订单号,交易创建时间,付款时间') ||
      compact.contains('支付宝支付科技有限公司电子客户回单') ||
      (compact.contains('交易时间,交易分类,交易对方') &&
          compact.contains('商品说明,收/支,金额,收/付款方式') &&
          compact.contains('交易订单号,商家订单号'))) {
    return StatementProvider.alipay;
  }
  if (compact.contains('微信支付账单明细') ||
      compact.contains('交易时间,交易类型,交易对方,商品,收/支')) {
    return StatementProvider.wechatPay;
  }
  if (compact.contains('借方金额') ||
      compact.contains('贷方金额') ||
      compact.contains('支出金额,收入金额') ||
      compact.contains('借方发生额') ||
      compact.contains('贷方发生额') ||
      compact.contains('借贷标志') ||
      compact.contains('借贷方向') ||
      compact.toLowerCase().contains('debit,credit')) {
    return StatementProvider.bank;
  }
  final lower = compact.toLowerCase();
  if (lower.contains('clientaccountid') ||
      lower.contains('interactivebrokers') ||
      lower.contains('ibkr') ||
      lower.contains('fees&comm') ||
      lower.contains('withholdingtax') ||
      lower.contains('futu') ||
      lower.contains('moomoo') ||
      compact.contains('富途') ||
      (compact.contains('证券代码') && compact.contains('手续费')) ||
      (lower.contains('symbol') &&
          lower.contains('amount') &&
          lower.contains('commission'))) {
    return StatementProvider.broker;
  }
  return StatementProvider.generic;
}

List<ParsedTransaction> parseStatementLedger(
  String raw, {
  StatementProvider provider = StatementProvider.auto,
  String defaultCurrency = 'CNY',
}) {
  final effective = provider == StatementProvider.auto
      ? detectStatementProvider(raw)
      : provider;
  return switch (effective) {
    StatementProvider.auto || StatementProvider.generic => parseCsvLedger(
      raw,
      defaultCurrency: defaultCurrency,
    ),
    StatementProvider.alipay => _parseAlipayLedger(
      raw,
      defaultCurrency: defaultCurrency,
    ),
    StatementProvider.wechatPay => parseCsvLedger(
      raw,
      defaultCurrency: defaultCurrency,
    ),
    StatementProvider.bank => parseBankCashLedger(
      raw,
      defaultCurrency: defaultCurrency,
    ),
    StatementProvider.broker => parseBrokerCashLedger(
      raw,
      defaultCurrency: defaultCurrency == 'CNY' ? 'USD' : defaultCurrency,
    ),
  };
}

List<ParsedTransaction> _parseAlipayLedger(
  String raw, {
  required String defaultCurrency,
}) {
  return parseCsvLedger(
        _preferAlipayPaidAt(raw),
        defaultCurrency: defaultCurrency,
      )
      .map((row) {
        final categoryHint = _alipayCategoryHint(row.description);
        return categoryHint == null
            ? row
            : row.copyWith(categoryHint: categoryHint);
      })
      .toList(growable: false);
}

/// Only map Alipay categories that have an unambiguous equivalent in the
/// FinanceOS taxonomy. Broad buckets such as “充值缴费” and “商业服务” stay
/// unset so the review step does not receive a confident but wrong category.
String? _alipayCategoryHint(String description) {
  const hints = <String, String>{
    '餐饮美食': 'dining',
    '日用百货': 'groceries',
    '住房物业': 'housing',
    '数码电器': 'shopping',
    '文化休闲': 'entertainment',
    '其他': 'other',
  };
  for (final part in description.split(' · ')) {
    final hint = hints[part.trim()];
    if (hint != null) return hint;
  }
  return null;
}

/// Alipay exports carry both creation and payment timestamps. The user's
/// ledger should use the payment time when it is available; creation time is
/// only a platform workflow timestamp. The generic parser picks the first
/// recognised date header, so make the creation column non-semantic before
/// delegating.
String _preferAlipayPaidAt(String raw) {
  return raw.replaceFirst('交易创建时间', '交易创建时间(平台)');
}
