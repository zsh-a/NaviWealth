/// `propose_asset_valuation` — device port.
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/propose_asset_valuation.rs`; logic a
/// verbatim port of `proposals::propose_asset_valuation`. Only valid
/// for manual-valuation asset types ([kProposalManualValuationTypes]) —
/// securities go through `propose_trade type=valuationAdjust`. Resolves
/// the asset against the device typed [allAssetsStreamProvider] list
/// (mirrors the backend `resolve_asset`). Returns the same
/// `ready_plan` / `needs_clarification` JSON; device never auto-writes
/// (§4.5).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/propose/proposal_plan.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

class ProposeAssetValuationTool implements DeviceTool {
  const ProposeAssetValuationTool();

  @override
  String get name => 'propose_asset_valuation';

  @override
  String get description =>
      '提议更新一个手工估值资产（房产 / 车 / 现金 / 银行存款 / 理财）的当前估值。'
      '有市场行情的证券请改用 propose_trade 的 valuationAdjust 类型。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['new_value'],
    'properties': {
      'asset_id': {'type': 'string'},
      'asset_symbol': {'type': 'string'},
      'asset_name': {'type': 'string'},
      'new_value': {'type': 'number', 'minimum': 0},
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
    final newValue = proposalRequireNum(input, 'new_value');
    if (newValue == null) {
      return proposalBadRequest("missing or non-numeric field 'new_value'");
    }
    if (newValue < 0) {
      return proposalBadRequest(
        'propose_asset_valuation: new_value must be ≥ 0',
      );
    }
    final warnings = <String>[];

    final assets = await ctx.ref.read(allAssetsStreamProvider.future);
    final resolved = resolveAsset(
      assets,
      byId: proposalOptionalStr(input, 'asset_id'),
      bySymbol: proposalOptionalStr(input, 'asset_symbol'),
      byName: proposalOptionalStr(input, 'asset_name'),
    );
    final asset = switch (resolved) {
      ResolvedOne(:final row) => row,
      ResolvedMany() => null,
      ResolvedNone() => null,
    };
    if (asset == null) {
      return switch (resolved) {
        ResolvedMany(:final candidates) => needsClarification(
          kind: 'asset_valuation',
          field: 'asset',
          reason: '存在多个匹配的资产，请让用户选择具体哪一个。',
          candidates: candidates,
        ),
        _ => needsClarification(
          kind: 'asset_valuation',
          field: 'asset',
          reason: '未找到匹配的资产。如果是新资产，请先用 propose_account_create 建立资产 / 账户。',
          candidates: const [],
        ),
      };
    }

    final assetType = asset.type.name;
    if (!kProposalManualValuationTypes.contains(assetType)) {
      return proposalBadRequest(
        "propose_asset_valuation: '$assetType' 不支持手工估值"
        '（请改用 propose_trade type=valuationAdjust）',
      );
    }

    // Backend: explicit → asset.currency → ('CNY' + warn). The device
    // `Asset.currency` is a required non-null field, so the 'CNY'+warn
    // arm is unreachable — faithfully, no currency warning here.
    final currency = proposalOptionalStr(input, 'currency') ?? asset.currency;

    final date = proposalOptionalStr(input, 'date');
    if (date != null) {
      if (!isRfc3339(date)) {
        return proposalBadRequest(
          "propose_asset_valuation: date '$date' is not RFC3339",
        );
      }
    } else {
      warnings.add('date 未指定，前端将默认为今天。');
    }

    final displayName = asset.name ?? asset.symbol;
    final payload = <String, Object?>{
      'type': 'asset_valuation',
      'asset_id': asset.id,
      'asset_name': displayName,
      'new_value': newValue,
      'currency': currency,
      'date': date,
      'note': proposalOptionalStr(input, 'note'),
    };

    return readyPlan(
      kind: 'asset_valuation',
      summaryZh:
          '更新「$displayName」估值为 ${formatProposalAmount(newValue)} $currency',
      payload: payload,
      warnings: warnings,
    );
  }
}
