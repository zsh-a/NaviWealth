/// Wave 26 — AI Transparency audit page.
///
/// Lists recent [AiTrace] records (newest first) from `recentAiTracesProvider`.
/// Tap a row to inspect: intent, routing reason, runtime, budget tier,
/// tool calls (with their freshness), disclosures, total duration, stale
/// read models. Trace storage is local-only — nothing here leaves the
/// device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../design_system/design_system.dart';

class AiTransparencyPage extends ConsumerWidget {
  const AiTransparencyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracesAsync = ref.watch(recentAiTracesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 透明度')),
      body: tracesAsync.when(
        data: (traces) {
          if (traces.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: traces.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) => _TraceRow(trace: traces[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '暂无 AI 调用记录。\n下次发起对话后，会在此处看到完整轨迹。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return ListTile(
      title: Text(
        (trace.intent.label?.isEmpty ?? true)
            ? '(unnamed turn)'
            : trace.intent.label!,
        style: ts.bodyLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(label: trace.backend.wire, tone: cs.primary),
            _Chip(label: '${trace.totalDurationMs} ms'),
            _Chip(label: trace.routingReason),
            _Chip(
              label: trace.terminalReason.wire,
              tone: trace.terminalReason == TerminalReason.done
                  ? cs.outline
                  : cs.error,
            ),
            if (trace.toolCalls.isNotEmpty)
              _Chip(label: '${trace.toolCalls.length} tools'),
            if (trace.staleReadModels > 0)
              _Chip(
                label: 'stale ×${trace.staleReadModels}',
                tone: cs.tertiary,
              ),
          ],
        ),
      ),
      trailing: Text(
        _shortTimestamp(trace.startedAtIso),
        style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      onTap: () => context.goNamed(
        AppRouteNames.aiTransparencyDetail,
        pathParameters: <String, String>{'requestId': trace.requestId},
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.tone});
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tone ?? cs.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class AiTransparencyDetailPage extends ConsumerWidget {
  const AiTransparencyDetailPage({super.key, required this.requestId});
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(aiTraceByIdProvider(requestId));
    return Scaffold(
      appBar: AppBar(title: const Text('调用详情')),
      body: traceAsync.when(
        data: (trace) {
          if (trace == null) {
            return const Center(child: Text('未找到该次调用记录'));
          }
          return _TraceDetail(trace: trace);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _TraceDetail extends StatelessWidget {
  const _TraceDetail({required this.trace});
  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: '基本',
          rows: <_KvRow>[
            _KvRow('Request ID', trace.requestId),
            _KvRow('开始时间', trace.startedAtIso),
            _KvRow('总耗时', '${trace.totalDurationMs} ms'),
            _KvRow('Backend', trace.backend.wire),
            _KvRow('Budget tier', trace.budgetTier.wire),
            _KvRow('路由原因', trace.routingReason),
            _KvRow(
              '原始 ledger',
              trace.usedRawLedger ? '触达' : '未触达',
            ),
            _KvRow('结束原因', trace.terminalReason.wire),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Intent',
          rows: <_KvRow>[
            _KvRow('capability', trace.intent.capability.wire),
            _KvRow('risk', trace.intent.risk.wire),
            _KvRow('label', trace.intent.label ?? ''),
          ],
        ),
        if (trace.toolCalls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(title: '工具调用 (${trace.toolCalls.length})'),
          for (final t in trace.toolCalls) _ToolCallTile(call: t),
        ],
        if (trace.staleReadModels > 0) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Stale read models (${trace.staleReadModels})',
          ),
          SoftCard(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in trace.staleReadModelNames)
                  _Chip(label: name),
              ],
            ),
          ),
        ],
        if (trace.disclosures.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Disclosures (${trace.disclosures.length})',
          ),
          for (final d in trace.disclosures) _DisclosureTile(d: d),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<_KvRow> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(title: title),
      SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final r in rows) _kvRow(context, r),
          ],
        ),
      ),
    ],
  );

  Widget _kvRow(BuildContext context, _KvRow r) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            r.k,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            r.v.isEmpty ? '—' : r.v,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _KvRow {
  const _KvRow(this.k, this.v);
  final String k;
  final String v;
}

class _ToolCallTile extends StatelessWidget {
  const _ToolCallTile({required this.call});
  final TraceToolCall call;

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(call.name, style: ts.bodyLarge)),
              _Chip(
                label: call.ok ? 'ok' : 'error',
                tone: call.ok ? cs.primary : cs.error,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${call.durationMs} ms',
              style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclosureTile extends StatelessWidget {
  const _DisclosureTile({required this.d});
  final DisclosureSummary d;

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.purpose.wire, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'consent: ${d.consent.wire} · rows: ${d.rowCount} · fields: ${d.fieldsCount}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

String _shortTimestamp(String iso) {
  if (iso.length < 16) return iso;
  // YYYY-MM-DDTHH:MM
  return iso.substring(5, 16).replaceFirst('T', ' ');
}
