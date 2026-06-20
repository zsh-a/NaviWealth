/// Per-message AI transparency badge.
///
/// Renders a one-line summary derived from the [AiTrace] keyed by the
/// chat message id. Silently absent when no trace is available
/// (legacy messages, in-flight messages, or failed prep).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AiTransparencyIndicator extends ConsumerWidget {
  const AiTransparencyIndicator({super.key, required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(aiTraceByIdProvider(messageId));
    final trace = traceAsync.asData?.value;
    if (trace == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final muted = context.theme.colors.mutedForeground;
    // Tappable: jumps to the existing per-trace detail page so the
    // user can drill into spans / tool I/O / disclosure summary. Tiny
    // info icon at the end advertises the affordance — the muted text
    // alone never read as a button.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s6),
      child: FTooltip(
        tipBuilder: (_, _) => Text(l10n.aiChatTransparencyOpenDetail),
        child: FTappable(
          onPress: () =>
              context.go(AppRoutes.settingsAiTransparencyDetail(messageId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    formatAiTraceBadge(trace),
                    style: context.captionStyle.copyWith(color: muted),
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.xs,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure formatter — exposed for tests. Joins the relevant axes of the
/// trace into a compact one-liner the user can read at a glance:
///
///   `本地数据 + 端侧推理 · 1 个工具 · 1.2s`
String formatAiTraceBadge(AiTrace trace) {
  final parts = <String>[];
  switch (trace.backend) {
    case Backend.device:
      // Device-LLM-direct (user's own key, straight to the
      // provider) and device Vision direct share the same "no
      // NaviWealth server" property; surface the distinction from the
      // zero-model rules-device path.
      parts.add(
        trace.routingReason == kDeviceLlmDirectRoutingReason ||
                trace.routingReason == kDeviceVisionDirectRoutingReason
            ? '端侧直连模型 · 请求与数据未经我方服务器'
            : '全部本地处理',
      );
    case Backend.cloud:
      parts.add('端侧模型推理');
    case Backend.hybrid:
      parts.add('本地数据 + 端侧推理');
  }
  if (trace.toolSpans.isNotEmpty) {
    parts.add('${trace.toolSpans.length} 个工具');
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
