/// `propose_income` — a user-confirmed generic cash-income proposal.
///
/// Like every Finance propose tool, this only returns a plan. The existing
/// proposal confirmation surface performs the audited ledger write.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

const Map<String, String> _incomeCategoryAliases = <String, String>{
  'salary': 'salary',
  '工资': 'salary',
  'dividend': 'dividend',
  '股息': 'dividend',
  '分红': 'dividend',
  'interest': 'interest',
  '利息': 'interest',
  'other': 'other',
  '其它': 'other',
  '其他': 'other',
};

class ProposeIncomeTool implements DeviceTool {
  const ProposeIncomeTool();

  @override
  String get name => 'propose_income';

  @override
  String get description => '提议一笔现金收入（工资、股息、利息或其它）。返回 plan，前端确认后才写入账本。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['amount'],
    'properties': {
      'amount': {'type': 'number', 'minimum': 0},
      'category': {
        'type': 'string',
        'enum': ['salary', 'dividend', 'interest', 'other'],
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
      return proposalBadRequest('propose_income: amount must be > 0');
    }
    final warnings = <String>[];
    final rawCategory = proposalOptionalStr(input, 'category');
    final category = rawCategory == null
        ? 'other'
        : _incomeCategoryAliases[rawCategory.trim().toLowerCase()];
    if (category == null) {
      return needsClarification(
        kind: 'income',
        field: 'category',
        reason: 'Choose one of the supported income categories.',
        candidates: const [
          {'id': 'salary', 'label': '工资'},
          {'id': 'dividend', 'label': '股息 / 分红'},
          {'id': 'interest', 'label': '利息'},
          {'id': 'other', 'label': '其它收入'},
        ],
      );
    }
    if (rawCategory == null) {
      warnings.add('category was not specified; defaulted to other.');
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
          kind: 'income',
          field: 'account',
          reason: 'Multiple accounts matched. Ask the user to choose one.',
          candidates: candidates,
        );
      case ResolvedNone():
        warnings.add(
          'account was not specified or did not match; the confirmation UI '
          'will ask the user to choose a destination account.',
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
    if (date != null && !isRfc3339(date)) {
      return proposalBadRequest("propose_income: date '$date' is not RFC3339");
    }
    if (date == null) {
      warnings.add(
        'date was not specified; the confirmation UI will default to today.',
      );
    }

    final payload = <String, Object?>{
      'type': 'income',
      'amount': amount,
      'category': category,
      'currency': currency,
      'account_id': account?.id,
      'account_name': account?.name,
      'date': date,
      'note': proposalOptionalStr(input, 'note'),
    };
    final accountPhrase = account == null ? '' : ' (${account.name})';
    return readyPlan(
      kind: 'income',
      summaryZh:
          'Record $category income ${formatProposalAmount(amount)} '
          '$currency$accountPhrase',
      payload: payload,
      warnings: warnings,
    );
  }
}
