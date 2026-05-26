import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/fire/data/fire_providers.dart';

/// `get_fire_buckets` — return the five-bucket coverage view plus
/// any holdings the allocator couldn't slot. Pure read.
class GetFireBucketsTool implements DeviceTool {
  const GetFireBucketsTool();

  @override
  String get name => 'get_fire_buckets';

  @override
  String get description =>
      '返回桶视图:现金 / 防御 / 增长 / 风险储备 / 梦想 五个角色的当前价值、目标、覆盖率和状态。'
      '同时返回 `unmapped_holdings`——这些资产暂未分配给任何桶,如果用户希望它们参与 FIRE 提取,'
      '请通过 `propose_fire_bucket_rule` 建议规则。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final async = ctx.ref.read(fireBucketAllocationProvider);
    final allocation = async.whenOrNull(data: (a) => a);
    if (allocation == null) {
      return <String, Object?>{
        'error': 'fire_buckets_unavailable',
        'code': 'unavailable',
      };
    }
    return <String, Object?>{
      'buckets': [
        for (final b in allocation.buckets)
          <String, Object?>{
            'role': b.role.name,
            'current_value': b.currentValue.amount.toString(),
            'target_value': b.targetValue.amount.toString(),
            'currency': b.currentValue.currency,
            'coverage_ratio': b.coverageRatio,
            'status': b.status.name,
            'asset_ids': b.assetIds,
          },
      ],
      'unmapped_holdings': [
        for (final u in allocation.unmappedHoldings)
          <String, Object?>{
            'id': u.id,
            'name': u.name,
            'value': u.value.amount.toString(),
            'currency': u.value.currency,
            'reason': u.reason,
          },
      ],
    };
  }
}
