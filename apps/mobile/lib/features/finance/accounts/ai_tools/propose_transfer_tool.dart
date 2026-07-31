import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

/// User-confirmed cash transfer between two existing payment accounts.
class ProposeTransferTool implements DeviceTool {
  const ProposeTransferTool();

  @override
  String get name => 'propose_transfer';

  @override
  String get description =>
      '提议账户间转账。必须明确来源和目标账户；跨币种时还必须提供目标账户实际到账金额。'
      '返回 plan，用户确认后才写入账本。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['amount'],
    'properties': {
      'amount': {'type': 'number', 'exclusiveMinimum': 0},
      'from_account_id': {'type': 'string'},
      'from_account_name': {'type': 'string'},
      'to_account_id': {'type': 'string'},
      'to_account_name': {'type': 'string'},
      'to_amount': {
        'type': 'number',
        'exclusiveMinimum': 0,
        'description': '跨币种转账时目标账户的实际到账金额',
      },
      'date': {'type': 'string', 'description': 'ISO-8601 timestamp'},
      'note': {'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final amount = proposalRequireNum(input, 'amount');
    if (amount == null || amount <= 0) {
      return proposalBadRequest('propose_transfer: amount must be > 0');
    }
    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    final fromResolved = resolveAccount(
      accounts,
      byId: proposalOptionalStr(input, 'from_account_id'),
      byName: proposalOptionalStr(input, 'from_account_name'),
    );
    final from = switch (fromResolved) {
      ResolvedOne(:final row) => row,
      _ => null,
    };
    if (from == null) {
      return needsClarification(
        kind: 'transfer',
        field: 'from_account',
        reason: fromResolved is ResolvedMany<Account>
            ? 'Multiple source accounts matched. Ask the user to choose one.'
            : 'A source account is required. Ask the user to choose one.',
        candidates: _accountCandidates(accounts, fromResolved),
      );
    }

    final toResolved = resolveAccount(
      accounts,
      byId: proposalOptionalStr(input, 'to_account_id'),
      byName: proposalOptionalStr(input, 'to_account_name'),
    );
    final to = switch (toResolved) {
      ResolvedOne(:final row) => row,
      _ => null,
    };
    if (to == null) {
      return needsClarification(
        kind: 'transfer',
        field: 'to_account',
        reason: toResolved is ResolvedMany<Account>
            ? 'Multiple destination accounts matched. Ask the user to choose one.'
            : 'A destination account is required. Ask the user to choose one.',
        candidates: _accountCandidates(
          accounts.where((account) => account.id != from.id).toList(),
          toResolved,
        ),
      );
    }
    if (from.id == to.id) {
      return proposalBadRequest(
        'propose_transfer: source and destination accounts must differ',
      );
    }

    final crossCurrency =
        from.currency.toUpperCase() != to.currency.toUpperCase();
    final toAmount = proposalRequireNum(input, 'to_amount');
    if (crossCurrency && (toAmount == null || toAmount <= 0)) {
      return needsClarification(
        kind: 'transfer',
        field: 'to_amount',
        reason:
            'Cross-currency transfer requires the actual destination amount '
            'in ${to.currency}.',
        candidates: const [],
      );
    }

    final date = proposalOptionalStr(input, 'date');
    if (date != null && !isRfc3339(date)) {
      return proposalBadRequest(
        "propose_transfer: date '$date' is not RFC3339",
      );
    }
    final payload = <String, Object?>{
      'type': 'transfer',
      'amount': amount,
      'from_account_id': from.id,
      'from_account_name': from.name,
      'from_currency': from.currency,
      'to_account_id': to.id,
      'to_account_name': to.name,
      'to_currency': to.currency,
      'to_amount': crossCurrency ? toAmount : null,
      'date': date,
      'note': proposalOptionalStr(input, 'note'),
    };
    final destinationAmount = crossCurrency
        ? ' → ${formatProposalAmount(toAmount!)} ${to.currency}'
        : '';
    return readyPlan(
      kind: 'transfer',
      summaryZh:
          'Transfer ${formatProposalAmount(amount)} ${from.currency} '
          'from ${from.name} to ${to.name}$destinationAmount',
      payload: payload,
      warnings: date == null
          ? const [
              'date was not specified; the confirmation UI will default to today.',
            ]
          : const [],
    );
  }
}

List<Map<String, Object?>> _accountCandidates(
  List<Account> accounts,
  ResolvedRef<Account> resolved,
) {
  if (resolved case ResolvedMany(:final candidates)) return candidates;
  return [
    for (final account in accounts.take(8))
      {
        'id': account.id,
        'name': account.name,
        'type': account.type.name,
        'currency': account.currency,
      },
  ];
}
