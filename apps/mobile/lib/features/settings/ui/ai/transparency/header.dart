part of '../ai_transparency_page.dart';

/// Verbose-capture switch. Off (default) = metadata-only spans; on =
/// also persist each step's input/output for deep debugging. Snapshot
/// per turn, so flipping it only affects future calls.
class _CaptureToggle extends ConsumerWidget {
  const _CaptureToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final verbose = ref.watch(aiTraceVerboseProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s4,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: SoftCard.flat(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiTransparencyVerboseTitle,
                    style: AiType.label(context),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.aiTransparencyVerboseSubtitle,
                    style: AiType.meta(
                      context,
                    ).copyWith(color: AiTone.muted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            AiPill(
              label: verbose
                  ? l10n.aiTransparencyToggleOn
                  : l10n.aiTransparencyToggleOff,
              state: verbose ? AiPillState.selected : AiPillState.neutral,
              onTap: () => ref.read(aiTraceVerboseProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opik-style aggregate strip over the recent-trace window: volume,
/// error rate, p50/p95 latency, token + cost totals. Doubles as the
/// "errors only" filter toggle.
class _AggregateHeader extends StatelessWidget {
  const _AggregateHeader({
    required this.traces,
    required this.errorsOnly,
    required this.onToggleErrors,
  });

  final List<AiTrace> traces;
  final bool errorsOnly;
  final VoidCallback onToggleErrors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final n = traces.length;
    final errors = traces
        .where((t) => t.terminalReason != TerminalReason.done)
        .length;
    final durations =
        traces.map((t) => t.totalDurationMs).toList(growable: false)..sort();
    final p50 = _pct(durations, 0.50);
    final p95 = _pct(durations, 0.95);
    var tokens = 0;
    var cost = 0.0;
    var hasCost = false;
    for (final t in traces) {
      tokens += t.tokenTotals.total;
      final c = estimateTraceCostCny(t);
      if (c != null) {
        cost += c;
        hasCost = true;
      }
    }
    final contextSummary = summarizeContextPackTraceWindow(traces);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: SoftCard.raised(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiTransparencyRecentCalls(n),
              style: AiType.bodyStrong(context),
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s6,
              children: [
                AiPill(
                  label: l10n.aiTransparencyErrors(errors),
                  state: errors > 0 && errorsOnly
                      ? AiPillState.error
                      : (errors > 0
                            ? AiPillState.selected
                            : AiPillState.neutral),
                  onTap: errors > 0 ? onToggleErrors : null,
                ),
                AiPill(label: 'p50 ${p50}ms'),
                AiPill(label: 'p95 ${p95}ms'),
                if (tokens > 0) AiPill(label: '$tokens tok'),
                if (hasCost) AiPill(label: '≈¥${cost.toStringAsFixed(3)}'),
                if (contextSummary.hasSamples) ...[
                  AiPill(
                    label:
                        'ctx samples ${contextSummary.sampleCount}/'
                        '${contextSummary.windowCount}',
                    state: contextSummary.sampleCoveragePercent < 80
                        ? AiPillState.selected
                        : AiPillState.neutral,
                  ),
                  AiPill(
                    label:
                        'ctx avg ${_formatBytes(contextSummary.avgPackBytes)}',
                  ),
                  AiPill(
                    label:
                        'ctx p95 ${_formatBytes(contextSummary.p95PackBytes)}',
                  ),
                  if (contextSummary.packBudgetBytes > 0)
                    AiPill(
                      label:
                          'ctx p95 '
                          '${contextSummary.p95PackBudgetPercent}% budget',
                      state: contextSummary.p95PackBudgetPercent >= 80
                          ? AiPillState.selected
                          : AiPillState.neutral,
                    ),
                  AiPill(
                    label:
                        'appendix avg '
                        '${_formatBytes(contextSummary.avgAppendixBytes)}',
                  ),
                  if (contextSummary.appendixCapBytes > 0)
                    AiPill(
                      label:
                          'appendix p95 '
                          '${contextSummary.p95AppendixCapPercent}% cap',
                      state: contextSummary.p95AppendixCapPercent >= 80
                          ? AiPillState.selected
                          : AiPillState.neutral,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static int _pct(List<int> sortedAsc, double q) {
    if (sortedAsc.isEmpty) return 0;
    final idx = ((sortedAsc.length - 1) * q).round();
    return sortedAsc[idx];
  }
}

/// Aggregate over recent trace root-span ContextPack sizing attributes.
///
/// This powers the batch-D decision about whether the ContextPack prompt
/// appendix is worth its byte cost. It intentionally ignores traces
/// written before these attributes existed, so the sample count is explicit.
class ContextPackTraceWindowSummary {
  const ContextPackTraceWindowSummary({
    required this.windowCount,
    required this.sampleCount,
    required this.avgPackBytes,
    required this.p95PackBytes,
    required this.packBudgetBytes,
    required this.avgAppendixBytes,
    required this.p95AppendixBytes,
    required this.appendixCapBytes,
  });

  final int windowCount;
  final int sampleCount;
  final int avgPackBytes;
  final int p95PackBytes;
  final int packBudgetBytes;
  final int avgAppendixBytes;
  final int p95AppendixBytes;
  final int appendixCapBytes;

  bool get hasSamples => sampleCount > 0;

  int get sampleCoveragePercent {
    if (windowCount <= 0) return 0;
    return (sampleCount / windowCount * 100).round();
  }

  int get p95PackBudgetPercent {
    if (packBudgetBytes <= 0) return 0;
    return (p95PackBytes / packBudgetBytes * 100).round();
  }

  int get p95AppendixCapPercent {
    if (appendixCapBytes <= 0) return 0;
    return (p95AppendixBytes / appendixCapBytes * 100).round();
  }
}

ContextPackTraceWindowSummary summarizeContextPackTraceWindow(
  List<AiTrace> traces,
) {
  final packBytes = <int>[];
  final appendixBytes = <int>[];
  var packBudgetBytes = 0;
  var appendixCapBytes = 0;
  for (final trace in traces) {
    final attrs = _turnAttributes(trace);
    final pack = _intAttr(attrs, 'context_pack_json_bytes');
    final appendix = _intAttr(attrs, 'context_appendix_bytes');
    if (pack == null || appendix == null) continue;
    packBytes.add(pack);
    appendixBytes.add(appendix);
    final budget = _intAttr(attrs, 'context_pack_budget_bytes');
    if (budget != null && budget > 0) packBudgetBytes = budget;
    final cap = _intAttr(attrs, 'context_appendix_cap_bytes');
    if (cap != null && cap > 0) appendixCapBytes = cap;
  }

  packBytes.sort();
  appendixBytes.sort();
  return ContextPackTraceWindowSummary(
    windowCount: traces.length,
    sampleCount: packBytes.length,
    avgPackBytes: _avg(packBytes),
    p95PackBytes: _pctInts(packBytes, 0.95),
    packBudgetBytes: packBudgetBytes,
    avgAppendixBytes: _avg(appendixBytes),
    p95AppendixBytes: _pctInts(appendixBytes, 0.95),
    appendixCapBytes: appendixCapBytes,
  );
}
