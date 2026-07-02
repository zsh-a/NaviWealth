import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

/// `propose_options_journal_entry` — propose a new entry on the options
/// trade journal (`docs/domains/options-income.md` §8.2).
///
/// Never writes directly. The front-end's confirm-and-apply pipeline
/// reads the returned ProposalEnvelope, shows the user a diff, and then
/// writes via [TradeJournalRepository].
class ProposeOptionsJournalEntryTool implements DeviceTool {
  const ProposeOptionsJournalEntryTool();

  @override
  String get name => 'propose_options_journal_entry';

  @override
  String get description =>
      '提议为期权交易日记新增一条记录 (strategy / underlying / option_symbol / '
      'opened_at_iso / entry_credit / currency / status / notes)。'
      '本工具不会立即写入,而是返回 plan,前端会展示 diff 并请用户确认。'
      '如果用户未提供 currency,默认使用 USD;status 默认 open。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': <String>[
      'strategy',
      'underlying',
      'option_symbol',
      'entry_credit',
    ],
    'properties': <String, Object?>{
      'strategy': <String, Object?>{
        'type': 'string',
        'enum': ['cash_secured_put', 'covered_call'],
      },
      'underlying': <String, Object?>{'type': 'string'},
      'option_symbol': <String, Object?>{'type': 'string'},
      'opened_at_iso': <String, Object?>{'type': 'string'},
      'entry_credit': <String, Object?>{'type': 'number', 'minimum': 0},
      'currency': <String, Object?>{
        'type': 'string',
        'minLength': 3,
        'maxLength': 8,
      },
      'status': <String, Object?>{
        'type': 'string',
        'enum': ['open', 'closed', 'assigned', 'expired'],
      },
      'notes': <String, Object?>{'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final strategy = parseOptionsStrategyKind(
      proposalRequireStr(input, 'strategy') ?? '',
    );
    final underlying = proposalRequireStr(input, 'underlying');
    final optionSymbol = proposalRequireStr(input, 'option_symbol');
    final credit = proposalRequireNum(input, 'entry_credit');
    if (strategy == null ||
        underlying == null ||
        optionSymbol == null ||
        credit == null) {
      return proposalBadRequest(
        'propose_options_journal_entry: missing required fields',
      );
    }
    final openedAt =
        proposalOptionalStr(input, 'opened_at_iso') ??
        DateTime.now().toUtc().toIso8601String();
    if (!isRfc3339(openedAt)) {
      return proposalBadRequest(
        'propose_options_journal_entry: opened_at_iso must be RFC3339',
      );
    }
    final currency = (proposalOptionalStr(input, 'currency') ?? 'USD')
        .toUpperCase();
    final statusRaw = proposalOptionalStr(input, 'status') ?? 'open';
    final status = parseTradeJournalStatus(statusRaw);
    final notes = proposalOptionalStr(input, 'notes');

    final payload = <String, Object?>{
      'strategy': strategy.wire,
      'underlying': underlying.toUpperCase(),
      'option_symbol': optionSymbol,
      'opened_at_iso': openedAt,
      'entry_credit': credit,
      'currency': currency,
      'status': status.wire,
      'notes': ?notes,
    };
    final action = strategy == OptionsStrategyKind.cashSecuredPut
        ? 'sell put'
        : 'covered call';
    final summary =
        '记录 ${underlying.toUpperCase()} $action — 收取权利金 $currency $credit';
    return readyPlan(
      kind: 'options_journal_entry',
      summaryZh: summary,
      payload: payload,
    );
  }
}
