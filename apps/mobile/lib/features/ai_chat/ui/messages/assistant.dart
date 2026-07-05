part of 'message_bubble.dart';

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.sessionId,
    required this.message,
    this.onReplyChip,
    this.onDecisionSelect,
    this.invocationIntent,
    this.isLastAssistant = false,
    this.suggestCannedReplies = true,
  });

  final String sessionId;
  final ChatMessage message;
  final void Function(String chip)? onReplyChip;
  final void Function(DecisionSelectionRequest selection)? onDecisionSelect;
  final String? invocationIntent;
  final bool isLastAssistant;
  final bool suggestCannedReplies;

  bool get _isError =>
      message.role == ChatRole.error ||
      message.status == ChatMessageStatus.errored;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final errorMessage = _localizedErrorMessage(context, message.errorMessage);
    // Calm error treatment (§5.6): the body — reasoning panel, tool
    // cards, model text — must stay readable. The error is signalled by
    // a soft destructive border + a leading ⚠ + the destructive
    // `errorMessage` line, never by drowning the whole bubble in a
    // saturated red fill (which tanks contrast on the muted reasoning
    // text). The icon is the a11y-friendly half of the cue — for users
    // who can't perceive the border tint, the icon + role announcement
    // still signal "this turn errored".
    final textColor = colors.foreground;
    final isStreaming = message.status == ChatMessageStatus.streaming;

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
        if (isStreaming && message.progress != null) ...[
          _LongTaskProgressRow(progress: message.progress!),
          const SizedBox(height: AppSpacing.s8),
        ],
        ..._buildInterleavedBlocks(
          context: context,
          textColor: textColor,
          isStreaming: isStreaming,
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
            !_isError &&
            message.role == ChatRole.assistant &&
            message.status == ChatMessageStatus.complete)
          AiTransparencyIndicator(messageId: message.id),
        // Inline per-message actions: copy (always on completed /
        // errored assistant rows) + regenerate (only on the trailing
        // assistant row, so a mid-thread tap can't silently discard
        // follow-up turns).
        if (!isStreaming && message.role == ChatRole.assistant)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s6),
            child: _AssistantActions(
              sessionId: sessionId,
              message: message,
              canRegenerate: isLastAssistant,
            ),
          ),
        // Generic rules-based reply chips under completed
        // assistant turns. Gated by [suggestCannedReplies] so the
        // conversation sheet stays quiet (it relies on the model's own
        // structured `ask_user` decision card instead — see
        // `_renderToolEntry`). The invocation surface keeps these as its
        // guided next-step affordance.
        if (onReplyChip != null &&
            suggestCannedReplies &&
            !isStreaming &&
            !_isError &&
            message.role == ChatRole.assistant &&
            message.status == ChatMessageStatus.complete)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: _ReplyChips(
              toolNames: {for (final t in message.toolCalls) t.name},
              invocationIntent: invocationIntent,
              onTap: onReplyChip!,
            ),
          ),
      ],
    );

    // One calm surface for every state. An abnormal end is marked by a
    // soft destructive hairline (accent, not fill) so the content stays
    // legible — matches the SoftCard / AiTone "error is an accent"
    // discipline used across the AI surfaces.
    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: _isError
              ? colors.destructive.withValues(alpha: AppOpacity.scrim)
              : colors.border,
          width: _isError ? AppStroke.medium : AppStroke.hairline,
        ),
      ),
      child: body,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AssistantAvatar(),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Semantics(
                container: true,
                label: _isError
                    ? l10n.aiChatSemanticsAssistantError
                    : l10n.aiChatSemanticsAssistantMessage,
                child: RepaintBoundary(child: bubble),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _localizedErrorMessage(BuildContext context, String? message) {
    if (message == null || message.isEmpty) return message;
    return switch (message) {
      'device_unavailable' => AppLocalizations.of(
        context,
      ).aiChatDeviceUnavailable,
      _ => message,
    };
  }

  /// Walks `displaySegments` and `toolCalls` in lock-step so the bubble
  /// renders text → tool → text → tool in the same order the model
  /// emitted them, instead of grouping all tool cards above a single
  /// concatenated paragraph.
  ///
  /// A pending propose-batch action header still floats to the top of
  /// the list because it is a per-turn summary, not a narrative element.
  List<Widget> _buildInterleavedBlocks({
    required BuildContext context,
    required Color textColor,
    required bool isStreaming,
  }) {
    final segments = message.displaySegments;
    final tools = message.toolCalls;
    final l10n = AppLocalizations.of(context);

    // Surface the optional batch propose-confirm header.
    final pending = <({ToolInvocation invocation, ReadyProposalPlan plan})>[];
    final plansById = <String, ProposalPlan>{};
    for (final t in tools) {
      if (!isProposeTool(t.name)) continue;
      final plan = ProposalPlan.tryParse(t.output);
      if (plan == null) continue;
      plansById[t.id] = plan;
      if (plan is ReadyProposalPlan) {
        final state = t.applyState ?? ProposalApplyState.pending;
        if (state.status == ProposalApplyStatus.pending ||
            state.status == ProposalApplyStatus.errored) {
          pending.add((invocation: t, plan: plan));
        }
      }
    }

    final blocks = <Widget>[];
    if (pending.length >= 2) {
      blocks.add(
        ProposeBatchActions(
          sessionId: sessionId,
          message: message,
          pending: pending,
        ),
      );
    }

    bool anythingEmittedYet = false;
    void addGapIfNeeded() {
      if (anythingEmittedYet) {
        blocks.add(const SizedBox(height: AppSpacing.s8));
      }
    }

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLastSeg = i == segments.length - 1;
      final shouldRenderText = seg.isNotEmpty || (isLastSeg && isStreaming);
      if (shouldRenderText) {
        addGapIfNeeded();
        // When the model is mid-flight and has called a tool
        // whose result hasn't arrived yet, surface the tool name so the
        // streaming indicator reads "正在 <tool>" instead of generic
        // "思考中". The pending tool is the *last* invocation without
        // output (per Anthropic's serial tool-use protocol).
        final pendingTool = (isLastSeg && isStreaming)
            ? _findPendingToolName(tools)
            : null;
        blocks.add(
          _AssistantBody(
            text: seg,
            isStreaming: isLastSeg && isStreaming,
            textColor: textColor,
            pendingToolName: pendingTool,
          ),
        );
        anythingEmittedYet = true;
      }
      if (i < tools.length) {
        addGapIfNeeded();
        blocks.add(_renderToolEntry(tools[i], plansById[tools[i].id], l10n));
        anythingEmittedYet = true;
      }
    }
    return blocks;
  }

  Widget _renderToolEntry(
    ToolInvocation invocation,
    ProposalPlan? plan,
    AppLocalizations l10n,
  ) {
    if (isProposeTool(invocation.name) && plan != null) {
      return ProposeCard(
        sessionId: sessionId,
        message: message,
        invocation: invocation,
        plan: plan,
      );
    }
    // Structured decision point (`ask_user`): render the interactive
    // choice card. Only the trailing turn's decision is actionable; a
    // tap sends the pick back as the next user turn via [onReplyChip].
    if (invocation.name == kAskUserToolName) {
      final request = DecisionRequest.tryParse(invocation.output);
      if (request != null) {
        final selected = invocation.decisionSelection;
        final interactive =
            selected == null &&
            isLastAssistant &&
            (onDecisionSelect != null || onReplyChip != null);
        return DecisionCard(
          request: request,
          selectedOptionId: selected?.optionId,
          interactive: interactive,
          onSelect: (option, reply) {
            final handler = onDecisionSelect;
            if (handler != null) {
              handler(
                DecisionSelectionRequest(
                  messageId: message.id,
                  toolInvocationId: invocation.id,
                  option: option,
                  reply: reply,
                ),
              );
              return;
            }
            onReplyChip?.call(reply);
          },
        );
      }
    }
    // Inline rendering when a domain renderer is registered;
    // the legacy card (chevron + raw JSON) remains the fallback for
    // tools without one, and accessible via long-press on the inline.
    return ToolInvocationInline(invocation: invocation);
  }
}

/// Last unresolved tool name. The model emits tool_use frames
/// serially under the Anthropic protocol, so the most recent
/// pending invocation is the one currently being awaited.
String? _findPendingToolName(List<ToolInvocation> tools) {
  for (var i = tools.length - 1; i >= 0; i--) {
    if (tools[i].status.isPending) return tools[i].name;
  }
  return null;
}
