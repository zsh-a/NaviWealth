/// `propose_liability_payment` — device port.
///
/// Schema + description verbatim from
/// the historical backend `propose_liability_payment` tool; logic a
/// verbatim port of `proposals::propose_liability_payment`. Resolves
/// the liability against `liabilitiesStreamProvider` and the optional
/// from-account against `accountsStreamProvider` (mirrors the backend
/// `resolve_liability` / `resolve_account`). Returns the same
/// `ready_plan` / `needs_clarification` JSON; device never auto-writes
/// (§4.5).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';

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
          reason: 'Multiple liabilities matched. Ask the user to choose one.',
          candidates: candidates,
        ),
        _ => needsClarification(
          kind: 'liability_payment',
          field: 'liability',
          reason:
              'No matching liability was found. Ask the user to add the loan '
              'or credit card first.',
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
          reason:
              'Multiple repayment accounts matched. Ask the user to choose one.',
          candidates: candidates,
        );
      case ResolvedNone():
        warnings.add(
          'from_account was not specified; the confirmation UI will ask the '
          'user to choose a repayment source account.',
        );
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
      warnings.add(
        'date was not specified; the confirmation UI will default to today.',
      );
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
          'Pay ${formatProposalAmount(amount)} $currency toward "${liability.name}"',
      payload: payload,
      warnings: warnings,
    );
  }
}
