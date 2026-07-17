part of 'message_bubble.dart';

class _AssistantBubble extends StatefulWidget {
  const _AssistantBubble({
    required this.sessionId,
    required this.message,
    this.onDecisionSelect,
    this.isLastAssistant = false,
  });

  final String sessionId;
  final ChatMessage message;
  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;
  final bool isLastAssistant;

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  /// Multi-tool group is collapsed by default when the turn is complete.
  bool _toolsExpanded = false;

  String get sessionId => widget.sessionId;
  ChatMessage get message => widget.message;
  bool get isLastAssistant => widget.isLastAssistant;
  void Function(DecisionSelectionRequest selection)? get onDecisionSelect =>
      widget.onDecisionSelect;

  bool get _isError =>
      message.role == ChatRole.error ||
      message.status == ChatMessageStatus.errored;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final errorMessage = _localizedErrorMessage(context, message.errorMessage);
    final textColor = colors.foreground;
    final isStreaming = message.status == ChatMessageStatus.streaming;
    final hasProgress = isStreaming && message.progress != null;

    final showTruncation =
        !isStreaming &&
        message.role == ChatRole.assistant &&
        message.status == ChatMessageStatus.complete &&
        (message.stopReason?.isAbnormal ?? false);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isError) ...[
          Row(
            children: [
              Icon(
                FLucideIcons.circleAlert,
                size: AppIconSizes.sm,
                color: colors.destructive,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                l10n.aiChatSemanticsAssistantError,
                style: context.captionLabelStyle.copyWith(
                  color: colors.destructive,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
        ],
        if ((message.reasoningText ?? '').isNotEmpty) ...[
          _ReasoningPanel(text: message.reasoningText!),
          const SizedBox(height: AppSpacing.s8),
        ],
        if (hasProgress) ...[
          _LongTaskProgressRow(progress: message.progress!),
          const SizedBox(height: AppSpacing.s8),
        ],
        ..._buildAnswerBlocks(
          context: context,
          textColor: textColor,
          isStreaming: isStreaming,
          suppressEmptyStatus: hasProgress,
        ),
        if (errorMessage != null && errorMessage.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            errorMessage,
            style: context.captionStyle.copyWith(
              color: context.theme.colors.destructive,
            ),
          ),
        ],
        if (showTruncation)
          _TruncationFooter(sessionId: sessionId, reason: message.stopReason!),
        if (!isStreaming &&
            message.role == ChatRole.assistant &&
            isLastAssistant)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: _AssistantActions(
              sessionId: sessionId,
              message: message,
              canRegenerate: true,
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Semantics(
        container: true,
        label: _isError
            ? l10n.aiChatSemanticsAssistantError
            : l10n.aiChatSemanticsAssistantMessage,
        child: DecoratedBox(
          decoration: _isError
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: colors.destructive.withValues(
                        alpha: AppOpacity.scrim,
                      ),
                      width: AppStroke.medium,
                    ),
                  ),
                )
              : const BoxDecoration(),
          child: Padding(
            padding: EdgeInsets.only(
              left: _isError ? AppSpacing.s10 : AppSpacing.s0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RepaintBoundary(child: body),
            ),
          ),
        ),
      ),
    );
  }

  String? _localizedErrorMessage(BuildContext context, String? raw) {
    if (raw == null || raw.isEmpty) return raw;
    return switch (raw) {
      'device_unavailable' => AppLocalizations.of(
        context,
      ).aiChatDeviceUnavailable,
      _ => raw,
    };
  }

  /// Answer-first layout:
  ///  1. prose (joined segments)
  ///  2. streaming status when no progress row
  ///  3. collapsed read-tool steps
  ///  4. propose / ask_user actions
  List<Widget> _buildAnswerBlocks({
    required BuildContext context,
    required Color textColor,
    required bool isStreaming,
    required bool suppressEmptyStatus,
  }) {
    final tools = message.toolCalls;
    final segments = message.displaySegments;

    final pendingBatch =
        <({ToolInvocation invocation, ReadyProposalPlan plan})>[];
    final readTools = <ToolInvocation>[];
    final actionWidgets = <Widget>[];

    for (final t in tools) {
      if (isProposeTool(t.name)) {
        final plan = ProposalPlan.tryParse(t.output);
        if (plan == null) continue;
        if (plan is ReadyProposalPlan) {
          final state = t.applyState ?? ProposalApplyState.pending;
          if (state.status == ProposalApplyStatus.pending ||
              state.status == ProposalApplyStatus.errored) {
            pendingBatch.add((invocation: t, plan: plan));
          }
        }
        actionWidgets.add(
          ProposeCard(
            sessionId: sessionId,
            message: message,
            invocation: t,
            plan: plan,
          ),
        );
        continue;
      }
      if (t.name == kAskUserToolName) {
        final request = DecisionRequest.tryParse(t.output);
        if (request != null) {
          final selected = t.decisionSelection;
          final interactive =
              selected == null &&
              isLastAssistant &&
              onDecisionSelect != null;
          actionWidgets.add(
            DecisionCard(
              request: request,
              selectedOptionId: selected?.optionId,
              interactive: interactive,
              onSelect: (option, reply) {
                onDecisionSelect?.call(
                  DecisionSelectionRequest(
                    messageId: message.id,
                    toolInvocationId: t.id,
                    option: option,
                    reply: reply,
                  ),
                );
              },
            ),
          );
          continue;
        }
      }
      readTools.add(t);
    }

    final blocks = <Widget>[];
    var emitted = false;
    void gap() {
      if (emitted) blocks.add(const SizedBox(height: AppSpacing.s8));
    }

    if (pendingBatch.length >= 2) {
      blocks.add(
        ProposeBatchActions(
          sessionId: sessionId,
          message: message,
          pending: pendingBatch,
        ),
      );
      emitted = true;
    }

    // Join non-empty prose segments into one readable answer body.
    final proseParts = [
      for (final s in segments)
        if (s.trim().isNotEmpty) s,
    ];
    final prose = proseParts.join('\n\n');
    final pendingTool = isStreaming ? _findPendingToolName(tools) : null;
    final showStreamingBody =
        isStreaming && !suppressEmptyStatus && prose.isEmpty;
    final showStreamingCaret = isStreaming && prose.isNotEmpty;

    if (prose.isNotEmpty || showStreamingBody) {
      gap();
      blocks.add(
        _AssistantBody(
          text: prose,
          isStreaming: showStreamingBody || showStreamingCaret,
          textColor: textColor,
          pendingToolName: showStreamingBody ? pendingTool : null,
        ),
      );
      emitted = true;
    } else if (isStreaming && !suppressEmptyStatus && pendingTool != null) {
      // Prose already rendered earlier this turn but a tool is pending —
      // surface it as a quiet status line (when progress row is absent).
      gap();
      blocks.add(
        _AssistantBody(
          text: '',
          isStreaming: true,
          textColor: textColor,
          pendingToolName: pendingTool,
        ),
      );
      emitted = true;
    }

    if (readTools.isNotEmpty) {
      gap();
      blocks.add(
        _ToolStepsGroup(
          tools: readTools,
          expanded: _toolsExpanded || isStreaming,
          onToggle: isStreaming
              ? null
              : () => setState(() => _toolsExpanded = !_toolsExpanded),
          isStreaming: isStreaming,
        ),
      );
      emitted = true;
    }

    for (final action in actionWidgets) {
      gap();
      blocks.add(action);
      emitted = true;
    }

    return blocks;
  }
}

/// Collapsed multi-tool summary; expands into quiet inline steps.
class _ToolStepsGroup extends StatelessWidget {
  const _ToolStepsGroup({
    required this.tools,
    required this.expanded,
    required this.onToggle,
    required this.isStreaming,
  });

  final List<ToolInvocation> tools;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AiTone.muted(context);

    // Single rich visualization: keep open so the chart is the answer.
    final single = tools.length == 1 ? tools.first : null;
    final singleRich =
        single != null &&
        !isStreaming &&
        single.output != null &&
        renderToolOutput(context, single.name, single.output) != null;
    if (singleRich) {
      return ToolInvocationInline(
        invocation: single,
        initiallyExpanded: true,
      );
    }

    final names = [for (final t in tools) friendlyToolName(l10n, t.name)];
    final summary = names.length <= 2
        ? names.join(' · ')
        : '${names.take(2).join(' · ')} +${names.length - 2}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FTappable(
          onPress: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Row(
              children: [
                Icon(FLucideIcons.wrench, size: AppIconSizes.xs, color: muted),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    '${l10n.aiChatToolsUsed(tools.length)}  ·  $summary',
                    style: AiType.meta(context).copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onToggle != null)
                  Icon(
                    expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                    size: AppIconSizes.xs,
                    color: muted,
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final t in tools)
            ToolInvocationInline(invocation: t, initiallyExpanded: false),
      ],
    );
  }
}

String? _findPendingToolName(List<ToolInvocation> tools) {
  for (var i = tools.length - 1; i >= 0; i--) {
    if (tools[i].status.isPending) return tools[i].name;
  }
  return null;
}
