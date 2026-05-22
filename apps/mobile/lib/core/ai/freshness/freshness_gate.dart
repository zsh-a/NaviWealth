/// Freshness gate (docs/ai-architecture.md §4.2 / §4.3).
///
/// 当云端 read model 返回 `freshness.source_hlc_watermark` 时，端侧用
/// 它与本地 HLC 比较：
///
///  - `localHlc > watermark` → 端侧有 op_log 还没被云端 read model 消费
///    （典型场景：用户刚录入交易，OpLog 还没 push / push 还没刷新
///    read model）。
///  - 反之 → read model 已经吃到端侧所有写入；不用走兜底通道。
///
/// Phase 1 只做判断 + 上报。Phase 2 在判断 stale 时通过新 SSE 事件
/// `request_freshness_refresh` 发起兜底通道，端侧把最小补丁回写云端。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../contracts/contracts.dart';

/// 端侧 HLC > read model 的 watermark 即认定 stale。HLC 的 canonical
/// 字符串形式 (`wallMillis.hex(counter)-nodeId`) 字典序与时序一致
/// (docs/sync-v2.md §4.1)，所以纯字符串比较够用。
///
/// 一个细节：localHlc 可能是 nil HLC（设备首次同步前）；那时
/// `wallMillis = 0` 一定小于任何真实 read model watermark，returns
/// false（不 stale）。
bool isStale({required Freshness cloud, required String localHlcText}) {
  if (cloud.sourceHlcWatermark.isEmpty) return false;
  if (localHlcText.isEmpty) return false;
  return localHlcText.compareTo(cloud.sourceHlcWatermark) > 0;
}

/// Snapshot of the gate evaluation for one trace entry.
class FreshnessVerdict {
  const FreshnessVerdict({
    required this.cloud,
    required this.localHlcText,
    required this.stale,
  });

  final Freshness cloud;
  final String localHlcText;
  final bool stale;
}

/// Async provider exposing the latest local HLC as canonical string.
/// `null` before the first stamp.
final localHlcStringProvider = FutureProvider<String?>((ref) async {
  final hlc = await ref.watch(syncLocalHlcProvider.future);
  return hlc?.toString();
});
