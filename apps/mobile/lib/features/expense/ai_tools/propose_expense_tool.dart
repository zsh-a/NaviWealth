/// `propose_expense` — device port.
///
/// Schema + description verbatim from
/// the historical backend `propose_expense` tool; logic a verbatim
/// port of `proposals::propose_expense`. Returns the shared
/// `ready_plan` / `needs_clarification` JSON, so the propose interception
/// + the existing
/// `ProposalEnvelope`/`proposal_applier` confirm flow consume it
/// unchanged — the device never auto-writes (§4.5).
///
/// Account resolution reads the device typed [Account] list via
/// `accountsStreamProvider` (active, non-system — same effective set as
/// the backend `deleted_at IS NULL`, and strictly safer for a
/// "pay-from" match since it can't resolve to a system counter-account).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

class ProposeExpenseTool implements DeviceTool {
  const ProposeExpenseTool();

  @override
  String get name => 'propose_expense';

  @override
  String get description =>
      '提议一笔日常消费 / 支出。返回 plan，前端确认后才写入 journal_entries / postings。'
      '类目从系统支出类目中选择，例如餐饮 / 咖啡 / 生鲜日用 / 订阅 / 购物 / 交通 / 其它。'
      '类目不在闭集时工具会返回 candidates，请你让用户选一个再重新调用。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['amount'],
    'properties': {
      'amount': {'type': 'number', 'minimum': 0},
      'category': {
        'type': 'string',
        'description': '中文 label 或 slug，如 餐饮 / dining / 咖啡 / coffee',
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
    final amount = proposalRequireNum(input, 'amount');
    if (amount == null) {
      return proposalBadRequest("missing or non-numeric field 'amount'");
    }
    if (amount <= 0) {
      return proposalBadRequest('propose_expense: amount must be > 0');
    }
    final rawCategory = proposalOptionalStr(input, 'category');
    final note = proposalOptionalStr(input, 'note');
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
                "Could not resolve '$rawCategory' against "
                '${kExpenseCategories.length} built-in categories. Ask the '
                'user to choose one of these three options.',
            candidates: [
              for (final (slug, label) in top3)
                <String, Object?>{'id': slug, 'label': label},
            ],
          );
      }
    } else {
      warnings.add(
        'category was not specified; defaulted to other for review.',
      );
      category = 'other';
    }

    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    Account? account;
    final resolved = resolveAccount(
      accounts,
      byId: proposalOptionalStr(input, 'account_id'),
      byName: proposalOptionalStr(input, 'account_name'),
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
        warnings.add(
          'account was not specified or did not match; the confirmation UI '
          'will ask the user to choose a payment account.',
        );
    }

    final currency =
        proposalOptionalStr(input, 'currency') ??
        account?.currency ??
        (() {
          warnings.add('currency was not specified; defaulted to CNY.');
          return 'CNY';
        })();

    final date = proposalOptionalStr(input, 'date');
    if (date != null) {
      if (!isRfc3339(date)) {
        return proposalBadRequest(
          "propose_expense: date '$date' is not RFC3339",
        );
      }
    } else {
      warnings.add(
        'date was not specified; the confirmation UI will default to today.',
      );
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
        '记一笔$label支出 ${formatProposalAmount(amount)} $currency$accountPhrase';

    return readyPlan(
      kind: 'expense',
      summaryZh: summary,
      payload: payload,
      warnings: warnings,
    );
  }
}
