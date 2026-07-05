import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_review.dart';

/// `get_fire_review` — return the latest deterministic periodic review.
///
/// `kind` selects monthly / quarterly / annual. The review is generated
/// on the fly from the current state + stress tests (cached snapshots
/// are not retrieved here — `propose_*` tools that want to compare
/// against history go through the cache directly).
class GetFireReviewTool implements DeviceTool {
  const GetFireReviewTool();

  @override
  String get name => 'get_fire_review';

  @override
  String get description =>
      '返回当前期(每月 / 每季 / 每年)的 FIRE 复盘报告——'
      '由本地确定性算法生成,findings 字段是 enum code,请按 code 转述含义,不要凭空增加结论。'
      '可用 kind 参数:monthly / quarterly / annual,默认 monthly。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'kind': <String, Object?>{
        'type': 'string',
        'enum': <String>['monthly', 'quarterly', 'annual'],
        'description': '复盘周期,默认 monthly。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final raw = (input['kind'] as String?)?.trim().toLowerCase() ?? 'monthly';
    final kind = FireReviewKind.values.firstWhere(
      (k) => k.name == raw,
      orElse: () => FireReviewKind.monthly,
    );
    final async = ctx.ref.read(fireLiveReviewProvider(kind));
    final review = async.whenOrNull(data: (r) => r);
    if (review == null) {
      return <String, Object?>{
        'error': 'review_unavailable',
        'code': 'unavailable',
      };
    }
    return review.toJson();
  }
}
