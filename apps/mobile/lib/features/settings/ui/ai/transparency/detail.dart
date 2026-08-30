part of '../ai_transparency_page.dart';

class _TraceWaterfallBody extends StatelessWidget {
  const _TraceWaterfallBody({required this.trace});

  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      children: [
        _HeaderSummary(trace: trace, eventCount: trace.spans.length),
        const SizedBox(height: AppSpacing.s20),
        if (trace.hasSpans)
          AiTraceWaterfall(trace: trace)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
            child: Text(
              AppLocalizations.of(context).aiTransparencyNoSpans,
              textAlign: TextAlign.center,
              style: AiType.body(context)
                  .copyWith(color: AiTone.muted(context)),
            ),
          ),
      ],
    );
  }
}

/// Compact summary above the waterfall. Mirrors the list-row chips plus the
/// request id, so users reporting bugs can quote it.
class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({required this.trace, required this.eventCount});

  final AiTrace trace;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final intent = trace.invocation?['intent']?.toString();
    final title =
        intent ?? trace.intent.label ?? l10n.aiTransparencyUnnamedTurn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AiSparkle(),
            const SizedBox(width: AppSpacing.s6),
            Expanded(child: Text(title, style: AiType.title(context))),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          l10n.aiTransparencyEventSummary(
            eventCount,
            _longTimestamp(trace.startedAtIso),
          ),
          style: AiType.meta(context),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(
          'request_id ${trace.requestId}',
          style: AiType.meta(context).copyWith(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
