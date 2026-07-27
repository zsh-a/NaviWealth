part of '../ai_transparency_page.dart';

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assistantAction = ref.watch(domainTabsAssistantActionProvider);
    return AppEmptyState(
      icon: FLucideIcons.eye,
      title: AppLocalizations.of(context).aiTransparencyEmpty,
      action: assistantAction == null
          ? null
          : FButton(
              variant: FButtonVariant.outline,
              onPress: () => assistantAction(context, ref),
              prefix: const Icon(FLucideIcons.sparkles, size: AppIconSizes.sm),
              child: Text(AppLocalizations.of(context).navAskAi),
            ),
    );
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.trace});

  final AiTrace trace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _displayTitle(trace, l10n);
    final source = _displaySource(trace);
    final isError = trace.terminalReason != TerminalReason.done;
    return AppTappable(
      onPress: () => context.goNamed(
        SettingsRouteNames.aiTransparencyDetail,
        pathParameters: <String, String>{'requestId': trace.requestId},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: _StatusDot(
                error: isError,
                color: isError ? AiTone.error(context) : AiTone.active(context),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AiType.label(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.s6,
                    children: [
                      if (source != null)
                        AiPill(label: source, state: AiPillState.selected),
                      AiPill(label: '${trace.totalDurationMs} ms'),
                      AiPill(label: trace.backend.wire),
                      if (trace.hasSpans && trace.tokenTotals.total > 0)
                        AiPill(label: '${trace.tokenTotals.total} tok'),
                      if (trace.toolSpans.isNotEmpty)
                        AiPill(
                          label: l10n.aiTransparencyToolsCount(
                            trace.toolSpans.length,
                          ),
                        ),
                      if (isError)
                        AiPill(
                          label: trace.terminalReason.wire,
                          state: AiPillState.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Text(
              _shortTimestamp(trace.startedAtIso),
              style: AiType.meta(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Prefer the invocation intent, then the intent label, and finally a
  /// generic placeholder.
  static String _displayTitle(AiTrace trace, AppLocalizations l10n) {
    final intent = trace.invocation?['intent']?.toString();
    if (intent != null && intent.isNotEmpty) return intent;
    final label = trace.intent.label;
    if (label != null && label.isNotEmpty) return label;
    return l10n.aiTransparencyUnnamedTurn;
  }

  /// `expense_detail * exp_123`, present only when the trace was triggered
  /// via an [AiIntentInvocation]. Manual chat-tab turns omit this chip.
  static String? _displaySource(AiTrace trace) {
    final source = trace.invocation?['source']?.toString();
    if (source == null || source.isEmpty) return null;
    final objType = trace.invocation?['object_type']?.toString();
    return objType != null && objType.isNotEmpty
        ? '$source \u00b7 $objType'
        : source;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.error, required this.color});

  final bool error;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppIconSizes.lg,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: AppSpacing.s8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
