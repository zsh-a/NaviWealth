/// `propose_expense` — device port (§4.6 W-D4.5).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/propose_expense.rs`; logic a verbatim
/// port of `proposals::propose_expense`. Returns the same
/// `ready_plan` / `needs_clarification` JSON the cloud tool returns, so
/// the W-D3 loop's propose interception + the existing
/// `ProposalEnvelope`/`proposal_applier` confirm flow consume it
/// unchanged — the device never auto-writes (§4.5).
///
/// Account resolution reads the device typed [Account] list via
/// `accountsStreamProvider` (active, non-system — same effective set as
/// the backend `deleted_at IS NULL`, and strictly safer for a
/// "pay-from" match since it can't resolve to a system counter-account).
library;

import '../../../../../data/domain/account.dart';
import '../../../../../data/repositories/providers.dart';
import 'device_tool.dart';
import 'propose/proposal_plan.dart';

class ProposeExpenseTool implements DeviceTool {
  const ProposeExpenseTool();

  @override
  String get name => 'propose_expense';

  @override
  String get description =>
      '提议一笔日常消费 / 支出。返回 plan，前端确认后才写入 journal_entries / postings。'
      '类目从内置 9 类里选：餐饮 / 交通 / 房租 / 娱乐 / 医疗 / 教育 / 购物 / 旅行 / 其它。'
      '类目不在闭集时工具会返回 candidates，请你让用户选一个再重新调用。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['amount'],
    'properties': {
      'amount': {'type': 'number', 'minimum': 0},
      'category': {
        'type': 'string',
        'description': '中文 label 或 slug，如 餐饮 / food',
      },
      'account_id': {'type': 'string'},
      'account_name': {'type': 'string'},
      'currency': {'type': 'string'},
      'date': {'type': 'string', 'description': 'ISO-8601'},
      'note': {'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final amount = _requireNum(input, 'amount');
    if (amount == null) {
      return proposalBadRequest("missing or non-numeric field 'amount'");
    }
    if (amount <= 0) {
      return proposalBadRequest('propose_expense: amount must be > 0');
    }
    final rawCategory = _optionalStr(input, 'category');
    final note = _optionalStr(input, 'note');
    final warnings = <String>[];

    final String category;
    if (rawCategory != null) {
      final match = matchExpenseCategory(rawCategory);
      switch (match) {
        case CategoryExact(:final slug):
          category = slug;
        case CategoryAmbiguous(:final top3):
          return needsClarification(
            kind: 'expense',
            field: 'category',
            reason:
                "无法在 ${kExpenseCategories.length} 个内置类目中确定 '$rawCategory'，"
                '请让用户从下面三个里选一个。',
            candidates: [
              for (final (slug, label) in top3)
                <String, Object?>{'id': slug, 'label': label},
            ],
          );
      }
    } else {
      warnings.add('category 未指定，已默认归入「其它」（用户可在确认页改）。');
      category = 'other';
    }

    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    Account? account;
    final resolved = resolveAccount(
      accounts,
      byId: _optionalStr(input, 'account_id'),
      byName: _optionalStr(input, 'account_name'),
    );
    switch (resolved) {
      case ResolvedOne(:final row):
        account = row;
      case ResolvedMany(:final candidates):
        return needsClarification(
          kind: 'expense',
          field: 'account',
          reason: '存在多个匹配的账户，请让用户选择具体哪一个。',
          candidates: candidates,
        );
      case ResolvedNone():
        warnings.add('account 未指定或未匹配；前端会让用户在确认页选择支付账户。');
    }

    final currency =
        _optionalStr(input, 'currency') ??
        account?.currency ??
        (() {
          warnings.add('currency 未指定，已默认 CNY');
          return 'CNY';
        })();

    final date = _optionalStr(input, 'date');
    if (date != null) {
      if (!isRfc3339(date)) {
        return proposalBadRequest(
          "propose_expense: date '$date' is not RFC3339",
        );
      }
    } else {
      warnings.add('date 未指定，前端将默认为今天。');
    }

    final payload = <String, Object?>{
      'type': 'expense',
      'amount': amount,
      'category': category,
      'currency': currency,
      'account_id': account?.id,
      'account_name': account?.name,
      'date': date,
      'note': note,
    };

    final label = kExpenseCategories
        .firstWhere((e) => e.$1 == category, orElse: () => ('other', '其它'))
        .$2;
    final accountPhrase = account != null ? '（${account.name}）' : '';
    final summary =
        '记一笔$label支出 ${_fmtAmount(amount)} $currency$accountPhrase';

    return readyPlan(
      kind: 'expense',
      summaryZh: summary,
      payload: payload,
      warnings: warnings,
    );
  }
}

/// `optional_str` — non-empty string field or null.
String? _optionalStr(Map<String, Object?> v, String key) {
  final x = v[key];
  return (x is String && x.isNotEmpty) ? x : null;
}

/// `require_num` — number or numeric string; null when missing/invalid.
double? _requireNum(Map<String, Object?> v, String key) {
  final x = v[key];
  if (x is num) return x.toDouble();
  if (x is String) return double.tryParse(x);
  return null;
}

/// Match Rust `format!("{}", f64)` for the summary: `12.0` → "12",
/// `12.5` → "12.5" (the payload keeps the raw double).
String _fmtAmount(double a) =>
    a == a.roundToDouble() ? a.toInt().toString() : a.toString();
