/// `propose_account_create` — device port.
///
/// Schema + description verbatim from
/// the historical backend `propose_account_create` tool; logic a
/// verbatim port of `proposals::propose_account_create`. Pure — no
/// reference resolution, no provider read — validates `type` against
/// the closed [kProposalAccountTypes] list and pre-allocates an id so
/// follow-up proposals can reference it. Returns the shared
/// `ready_plan` / `needs_clarification` JSON consumed by the confirm
/// flow; the device never auto-writes (§4.5).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/shared/propose/proposal_plan.dart';

class ProposeAccountCreateTool implements DeviceTool {
  const ProposeAccountCreateTool();

  @override
  String get name => 'propose_account_create';

  @override
  String get description =>
      '提议创建一个新账户（券商 / 银行 / 现金 / 实物资产 / 负债）。返回 plan + 预分配 id。'
      '后续 propose_trade / propose_expense 可以引用这个 id。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['name', 'type'],
    'properties': {
      'name': {'type': 'string'},
      'type': {'type': 'string', 'enum': kProposalAccountTypes},
      'currency': {'type': 'string', 'default': 'CNY'},
      'institution': {'type': 'string'},
      'note': {'type': 'string'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final name = proposalRequireStr(input, 'name');
    if (name == null) {
      return proposalBadRequest("missing or non-string field 'name'");
    }
    if (name.trim().isEmpty) {
      return proposalBadRequest(
        'propose_account_create: name must not be blank',
      );
    }
    final acctType = proposalRequireStr(input, 'type');
    if (acctType == null) {
      return proposalBadRequest("missing or non-string field 'type'");
    }
    if (!kProposalAccountTypes.contains(acctType)) {
      return needsClarification(
        kind: 'account_create',
        field: 'type',
        reason:
            "'$acctType' is not a valid account type. Ask the user to choose "
            'one of these options.',
        candidates: [
          for (final t in kProposalAccountTypes)
            <String, Object?>{'id': t, 'label': t},
        ],
      );
    }

    final explicitCurrency = proposalOptionalStr(input, 'currency');
    final currency = explicitCurrency ?? 'CNY';
    final warnings = <String>[
      if (explicitCurrency == null)
        'currency was not specified; defaulted to CNY.',
    ];

    final payload = <String, Object?>{
      'id': proposalNewId(),
      'name': name,
      'type': acctType,
      'currency': currency,
      'institution': proposalOptionalStr(input, 'institution'),
      'note': proposalOptionalStr(input, 'note'),
    };

    return readyPlan(
      kind: 'account_create',
      summaryZh: 'Create account "$name" ($acctType / $currency)',
      payload: payload,
      warnings: warnings,
    );
  }
}
