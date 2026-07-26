import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';

/// Stages a long-call overlay record for explicit user confirmation.
class ProposeLeapsCallPositionTool implements DeviceTool {
  const ProposeLeapsCallPositionTool();

  @override
  String get name => 'propose_leaps_call_position';

  @override
  String get description =>
      '提议记录一笔独立于 Wheel 阶段的长期 Long Call（LEAPS）持仓。'
      '需要标的、合约代码、开仓日、到期日、行权价和每张买入权利金；'
      '可选填写手工市值与 Delta。不会直接写入，必须由用户确认。'
      '不得将它描述为备兑 Call、PMCC 或 Wheel 的新阶段。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': [
      'underlying',
      'option_symbol',
      'opened_at_iso',
      'expiration_at_iso',
      'strike_price',
      'entry_debit',
    ],
    'properties': <String, Object?>{
      'underlying': <String, Object?>{'type': 'string'},
      'option_symbol': <String, Object?>{'type': 'string'},
      'opened_at_iso': <String, Object?>{'type': 'string'},
      'expiration_at_iso': <String, Object?>{'type': 'string'},
      'strike_price': <String, Object?>{
        'type': 'number',
        'exclusiveMinimum': 0,
      },
      'entry_debit': <String, Object?>{'type': 'number', 'exclusiveMinimum': 0},
      'fees': <String, Object?>{'type': 'number', 'minimum': 0},
      'contract_quantity': <String, Object?>{'type': 'integer', 'minimum': 1},
      'contract_size': <String, Object?>{'type': 'integer', 'minimum': 1},
      'currency': <String, Object?>{'type': 'string'},
      'brokerage_account_id': <String, Object?>{'type': 'string'},
      'cash_account_id': <String, Object?>{'type': 'string'},
      'underlying_market': <String, Object?>{'type': 'string'},
      'current_mark': <String, Object?>{'type': 'number', 'minimum': 0},
      'current_delta': <String, Object?>{
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
      },
      'notes': <String, Object?>{'type': 'string'},
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final underlying = proposalRequireStr(input, 'underlying');
    final optionSymbol = proposalRequireStr(input, 'option_symbol');
    final openedAt = proposalRequireStr(input, 'opened_at_iso');
    final expirationAt = proposalRequireStr(input, 'expiration_at_iso');
    final strike = proposalRequireNum(input, 'strike_price');
    final debit = proposalRequireNum(input, 'entry_debit');
    if (underlying == null ||
        optionSymbol == null ||
        openedAt == null ||
        expirationAt == null ||
        strike == null ||
        debit == null ||
        strike <= 0 ||
        debit <= 0 ||
        !isRfc3339(openedAt) ||
        !isRfc3339(expirationAt)) {
      return proposalBadRequest(
        'propose_leaps_call_position: required fields are missing or invalid',
      );
    }
    final openDate = DateTime.parse(openedAt);
    final expiryDate = DateTime.parse(expirationAt);
    if (!expiryDate.isAfter(openDate)) {
      return proposalBadRequest(
        'propose_leaps_call_position: expiration must be after open date',
      );
    }
    final fees = proposalRequireNum(<String, Object?>{
      'fees': input['fees'] ?? 0,
    }, 'fees');
    final hasMark = input.containsKey('current_mark');
    final hasDelta = input.containsKey('current_delta');
    final mark = hasMark ? proposalRequireNum(input, 'current_mark') : null;
    final delta = hasDelta ? proposalRequireNum(input, 'current_delta') : null;
    final quantity = (input['contract_quantity'] as num?)?.toInt() ?? 1;
    final size = (input['contract_size'] as num?)?.toInt() ?? 100;
    if (fees == null ||
        fees < 0 ||
        quantity < 1 ||
        size < 1 ||
        (hasMark && (mark == null || mark < 0)) ||
        (hasDelta && (delta == null || delta < 0 || delta > 1))) {
      return proposalBadRequest(
        'propose_leaps_call_position: optional values are invalid',
      );
    }
    final currency = (proposalOptionalStr(input, 'currency') ?? 'USD')
        .toUpperCase();
    return readyPlan(
      kind: 'leaps_call_position',
      summaryZh:
          '记录 ${underlying.toUpperCase()} LEAPS Long Call — 支出 $currency $debit/张',
      payload: <String, Object?>{
        'underlying': underlying.toUpperCase(),
        'option_symbol': optionSymbol,
        'opened_at_iso': openDate.toUtc().toIso8601String(),
        'expiration_at_iso': expiryDate.toUtc().toIso8601String(),
        'strike_price': strike,
        'entry_debit': debit,
        'fees': fees,
        'contract_quantity': quantity,
        'contract_size': size,
        'currency': currency,
        'brokerage_account_id': ?proposalOptionalStr(
          input,
          'brokerage_account_id',
        ),
        'cash_account_id': ?proposalOptionalStr(input, 'cash_account_id'),
        'underlying_market': ?proposalOptionalStr(input, 'underlying_market'),
        'status': LeapsCallStatus.open.wire,
        'current_mark': ?mark,
        'current_delta': ?delta,
        if (mark != null)
          'marked_at_iso': DateTime.now().toUtc().toIso8601String(),
        'notes': ?proposalOptionalStr(input, 'notes'),
      },
    );
  }
}
