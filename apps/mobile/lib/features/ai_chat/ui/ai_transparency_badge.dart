/// Per-message AI transparency badge.
///
/// Renders a one-line summary derived from the [AiTrace] keyed by the
/// chat message id. Silently absent when no trace is available
/// (legacy messages, in-flight messages, or failed prep).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/trace.dart';

class AiTransparencyBadge extends ConsumerWidget {
  const AiTransparencyBadge({super.key, required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(aiTraceByIdProvider(messageId));
    final trace = traceAsync.asData?.value;
    if (trace == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        formatAiTraceBadge(trace),
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }
}

/// Pure formatter — exposed for tests. Joins the relevant axes of the
/// trace into a compact one-liner the user can read at a glance:
///
///   `本地数据 + 云端推理 · 未上传原始交易明细 · 1 个工具 · 1.2s`
String formatAiTraceBadge(AiTrace trace) {
  final parts = <String>[];
  switch (trace.backend) {
    case Backend.device:
      // §4.6 W-D6 — device-LLM-direct (user's own key, straight to the
      // provider) is materially more private than the zero-model
      // rules-device path; surface the distinction.
      parts.add(
        trace.routingReason == kDeviceLlmDirectRoutingReason
            ? '端侧直连模型 · 请求与数据未经我方服务器'
            : '全部本地处理',
      );
    case Backend.cloud:
      parts.add('仅云端推理');
    case Backend.hybrid:
      parts.add('本地数据 + 云端推理');
  }
  parts.add(trace.usedRawLedger ? '已授权使用明细数据' : '未上传原始交易明细');
  if (trace.toolCalls.isNotEmpty) {
    parts.add('${trace.toolCalls.length} 个工具');
  }
  // 当云端 read model 落后本地写入时，提示数据陈旧（freshness gate
  // §4.2 兜底通道的轻量级形态：日志 + 用户可见提示，不重发请求）。
  if (trace.staleReadModels > 0) {
    parts.add('${trace.staleReadModels} 项数据滞后');
  }
  parts.add(_formatDuration(trace.totalDurationMs));
  return parts.join(' · ');
}

String _formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000.0;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  return '${seconds.round()}s';
}
