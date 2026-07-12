part of 'message_bubble.dart';

class _LongTaskProgressRow extends StatelessWidget {
  const _LongTaskProgressRow({required this.progress});

  final LongTaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ratio = progress.normalisedRatio;
    final toolName = progress.label == 'tool' ? progress.detail : null;
    final label = toolName == null
        ? progress.label
        : l10n.aiChatRunningTool(friendlyToolName(l10n, toolName));
    final detail = toolName == null ? progress.detail : null;
    final active = AiTone.active(context);
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active.withValues(alpha: AppOpacity.subtle),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active.withValues(alpha: AppOpacity.focusRing),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AiSparkle(active: true),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      label,
                      style: AiType.metaStrong(context).copyWith(color: active),
                    ),
                  ),
                ],
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(detail, style: context.captionStyle),
              ],
              const SizedBox(height: AppSpacing.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: ratio,
                  backgroundColor: active.withValues(alpha: AppOpacity.subtle),
                  valueColor: AlwaysStoppedAnimation<Color>(active),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantBody extends StatelessWidget {
  const _AssistantBody({
    required this.text,
    required this.isStreaming,
    required this.textColor,
    this.pendingToolName,
  });
  final String text;
  final bool isStreaming;
  final Color textColor;

  /// When the model has dispatched a tool but is still
  /// waiting for the result, surface the tool name. Beats a generic
  /// "thinking" placeholder for agentic flows.
  final String? pendingToolName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (text.isEmpty && isStreaming) {
      // Active-tool variant: replace dots + 思考中 with
      // ✦ 正在 get_holdings ... so the user can see what the agent is
      // doing right now.
      if (pendingToolName != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AiSparkle(active: true),
            const SizedBox(width: AppSpacing.s6),
            Text(
              // Pass the friendly localized tool name (e.g. "查询持仓")
              // instead of the wire id — generic users shouldn't need to
              // decode `get_holdings`, and we drop the monospace face so
              // mixed CJK/ASCII renders consistently.
              l10n.aiChatRunningTool(friendlyToolName(l10n, pendingToolName!)),
              style: AiType.meta(
                context,
              ).copyWith(color: AiTone.active(context)),
            ),
            const SizedBox(width: AppSpacing.s2),
            _TypingDots(
              color: AiTone.active(
                context,
              ).withValues(alpha: AppOpacity.strong),
            ),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(color: textColor.withValues(alpha: AppOpacity.strong)),
          const SizedBox(width: AppSpacing.s8),
          Text(
            l10n.aiChatThinking,
            style: context.theme.typography.body.sm.copyWith(
              color: textColor.withValues(alpha: AppOpacity.strong),
            ),
          ),
        ],
      );
    }
    final base = context.theme.typography.body.sm.copyWith(
      color: textColor,
      height: 1.5,
    );
    return AiMarkdown(
      text: text,
      baseStyle: base,
      trailing: isStreaming
          ? WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s4),
                child: _StreamingCaret(color: textColor),
              ),
            )
          : null,
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotionPolicy.isEnabled(context, role: AppMotionRole.status)) {
      _ctrl
        ..stop()
        ..value = 1;
      return;
    }
    _ctrl
      ..duration = Motion.typingCycle
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s4),
              _dot(i),
            ],
          ],
        );
      },
    );
  }

  Widget _dot(int index) {
    // Each dot peaks ~133ms apart over the 1200ms cycle.
    final phase = (_ctrl.value - index * 0.111) % 1.0;
    final scale = 0.6 + 0.4 * (1 - (phase - 0.3).abs() * 3).clamp(0.0, 1.0);
    final alpha = 0.4 + 0.6 * (1 - (phase - 0.3).abs() * 3).clamp(0.0, 1.0);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: AppSpacing.s6,
        height: AppSpacing.s6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: alpha),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret({required this.color});
  final Color color;

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotionPolicy.isEnabled(context, role: AppMotionRole.status)) {
      _ctrl
        ..stop()
        ..value = 1;
      return;
    }
    _ctrl
      ..duration = Motion.caretBlink
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_ctrl),
      child: Container(
        width: 6,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

class _ReasoningPanel extends StatefulWidget {
  const _ReasoningPanel({required this.text});

  final String text;

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final labelStyle = context.captionLabelStyle.copyWith(
      color: colors.mutedForeground,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FTappable(
          onPress: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).aiChatThinking,
                  style: labelStyle,
                ),
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                  size: AppIconSizes.sm,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            // Reasoning is free-form LLM prose — frequently contains
            // headings, lists, inline code (especially for tool-call
            // explanations), so we render through AiMarkdown so the
            // panel matches the visual language of the main bubble.
            child: AiMarkdown(
              text: widget.text,
              baseStyle: context.captionStyle.copyWith(height: 1.45),
            ),
          ),
      ],
    );
  }
}
