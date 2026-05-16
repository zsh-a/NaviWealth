/// `propose_liability_payment` — device port (§4.6 W-D4.5c).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/propose_liability_payment.rs`; logic a
/// verbatim port of `proposals::propose_liability_payment`. Resolves
/// the liability against `liabilitiesStreamProvider` and the optional
/// from-account against `accountsStreamProvider` (mirrors the backend
/// `resolve_liability` / `resolve_account`). Returns the same
/// `ready_plan` / `needs_clarification` JSON; device never auto-writes
/// (§4.5).
library;

import '../../../../../data/domain/account.dart';
import '../../../../../data/repositories/providers.dart';
import '../../../../../features/liabilities/data/providers.dart';
import 'device_tool.dart';
import 'propose/proposal_plan.dart';

class ProposeLiabilityPaymentTool implements DeviceTool {
  const ProposeLiabilityPaymentTool();

  @override
  String get name => 'propose_liability_payment';

  @override
  String get description =>
      '提议一笔负债还款（房贷、信用卡、消费贷等）。返回 plan，前端确认后走还款流程。'
      'liability 通过 liability_id 或 liability_name 指认；金额 > 0。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['amount'],
    'properties': {
      'liability_id': {'type': 'string'},
      'liability_name': {'type': 'string'},
      'from_account_id': {'type': 'string', 'description': '还款来源账户'},
      'from_account_name': {'type': 'string'},
      'amount': {'type': 'number', 'minimum': 0},
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
      return proposalBadRequest(
        'propose_liability_payment: amount must be > 0',
      );
    }
    final note = proposalOptionalStr(input, 'note');
    final warnings = <String>[];

    final liabilities = await ctx.ref.read(liabilitiesStreamProvider.future);
    final resolvedL = resolveLiability(
      liabilities,
      byId: proposalOptionalStr(input, 'liability_id'),
      byName: proposalOptionalStr(input, 'liability_name'),
    );
    final liability = switch (resolvedL) {
      ResolvedOne(:final row) => row,
      _ => null,
    };
    if (liability == null) {
      return switch (resolvedL) {
        ResolvedMany(:final candidates) => needsClarification(
          kind: 'liability_payment',
          field: 'liability',
          reason: '存在多个匹配的负债，请让用户选择具体哪一笔。',
          candidates: candidates,
        ),
        _ => needsClarification(
          kind: 'liability_payment',
          field: 'liability',
          reason: '未找到匹配的负债。请让用户先在「负债」里录入这笔贷款 / 信用卡。',
          candidates: const [],
        ),
      };
    }

    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    final resolvedA = resolveAccount(
      accounts,
      byId: proposalOptionalStr(input, 'from_account_id'),
      byName: proposalOptionalStr(input, 'from_account_name'),
    );
    Account? fromAccount;
    switch (resolvedA) {
      case ResolvedOne(:final row):
        fromAccount = row;
      case ResolvedMany(:final candidates):
        return needsClarification(
          kind: 'liability_payment',
          field: 'from_account',
          reason: '存在多个匹配的还款账户，请让用户选择具体哪一个。',
          candidates: candidates,
        );
      case ResolvedNone():
        warnings.add('from_account 未指定，前端会让用户在确认页选择还款来源账户。');
    }

    // Backend: explicit → liability.currency → ('CNY' + warn). Device
    // Liability.currency is required non-null, so the CNY+warn arm is
    // unreachable — faithfully no currency warning.
    final currency =
        proposalOptionalStr(input, 'currency') ?? liability.currency;

    final date = proposalOptionalStr(input, 'date');
    if (date != null) {
      if (!isRfc3339(date)) {
        return proposalBadRequest(
          "propose_liability_payment: date '$date' is not RFC3339",
        );
      }
    } else {
      warnings.add('date 未指定，前端将默认为今天。');
    }

    final payload = <String, Object?>{
      'type': 'liabilityPayment',
      'liability_id': liability.id,
      'liability_name': liability.name,
      'from_account_id': fromAccount?.id,
      'from_account_name': fromAccount?.name,
      'amount': amount,
      'currency': currency,
      'date': date,
      'note': note,
    };

    return readyPlan(
      kind: 'liability_payment',
      summaryZh:
          '向「${liability.name}」还款 ${formatProposalAmount(amount)} $currency',
      payload: payload,
      warnings: warnings,
    );
  }
}
