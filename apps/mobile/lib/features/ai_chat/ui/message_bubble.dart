import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;
import '../../../core/ai/visual/visual.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/chat_models.dart';
import '../state/chat_controller.dart';
import 'ai_transparency_badge.dart';
import 'decision_card.dart';
import 'decision_request.dart';
import 'propose_card.dart';
import 'reply_chips.dart';
import 'tool_invocation_card.dart' show friendlyToolName;
import 'tool_invocation_inline.dart';

/// Renders a single chat row. Roles map to distinct visual treatments:
///
///  - `user` — right-aligned filled bubble in the primary container.
///  - `assistant` — left-aligned with a subtle surface bubble; tool
///    invocations stack underneath.
///  - `system` — centered chip-style notice ("已折叠 N 条历史").
///  - `error` — left-aligned bubble in the error container colour.
///
/// Streaming assistant turns get a small pulsing dot at the end of the
/// text so the user can tell content is still arriving.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.sessionId,
    required this.message,
    this.onReplyChip,
    this.invocationIntent,
    this.isLastAssistant = false,
    this.isLastUser = false,
    this.suggestCannedReplies = true,
  });

  final String sessionId;
  final ChatMessage message;

  /// When non-null, completed assistant turns render reply
  /// chips below the body and call this back with the tapped chip
  /// text. Caller sends it as the next user turn. Streaming/error
  /// messages render no chips regardless.
  final void Function(String chip)? onReplyChip;

  /// When false, the generic rules-based reply chips
  /// (`suggestReplyChips`) are suppressed — only a content-derived
  /// clickable choice list (parsed from a menu the model actually wrote)
  /// renders. The conversation sheet sets this false so every turn isn't
  /// trailed by canned "展开细节 / 对比" suggestions; the invocation
  /// surface keeps them (true) as its guided next-step affordance.
  final bool suggestCannedReplies;

  /// Invocation intent that triggered this turn. Drives the rules-based chip suggester.
  final String? invocationIntent;

  /// Whether this is the trailing assistant message in the timeline.
  /// Only the trailing one gets a "regenerate" affordance — discarding
  /// a mid-thread assistant reply would silently throw away every
  /// follow-up turn, which is almost never what the user wants.
  final bool isLastAssistant;

  /// Whether this is the trailing user message in the timeline. Only
  /// the trailing user message gets the "edit & resend" affordance —
  /// mid-thread edit would silently discard every follow-up turn,
  /// which is destructive and almost never the user intent.
  final bool isLastUser;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (message.role) {
      ChatRole.system => _SystemNotice(text: message.content),
      ChatRole.user => _UserBubble(
        sessionId: sessionId,
        message: message,
        isLastUser: isLastUser,
      ),
      ChatRole.assistant || ChatRole.error => _AssistantBubble(
        sessionId: sessionId,
        message: message,
        onReplyChip: onReplyChip,
        invocationIntent: invocationIntent,
        isLastAssistant: isLastAssistant,
        suggestCannedReplies: suggestCannedReplies,
      ),
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey(message.id),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.medium,
      curve: Motion.standardDecelerate,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _UserBubble extends ConsumerWidget {
  const _UserBubble({
    required this.sessionId,
    required this.message,
    this.isLastUser = false,
  });

  final String sessionId;
  final ChatMessage message;

  /// Only the trailing user message gets the edit-and-resend
  /// affordance — see [MessageBubble.isLastUser].
  final bool isLastUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final turn = ref.watch(chatControllerProvider(sessionId));
    // Edit is gated to: (a) the trailing user turn, (b) not currently
    // streaming/flushing — otherwise tapping mid-stream would race the
    // in-flight pipeline and produce duplicates.
    final showEdit = isLastUser && !turn.isBusy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Semantics(
                    container: true,
                    label: l10n.aiChatSemanticsUserMessage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(4),
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: SelectableText(
                        message.content,
                        style: typography.sm.copyWith(
                          height: 1.5,
                          color: colors.primaryForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: _ActionButton(
                icon: FLucideIcons.pencil,
                label: l10n.aiChatEditUserMessage,
                onPressed: () => _editAndResend(context, ref),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editAndResend(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: message.content);
    final result = await showAppFormSheet<String>(
      context: context,
      builder: (ctx) => AppSheet(
        title: l10n.aiChatEditUserMessageTitle,
        footer: AppSheetFooter(
          submitLabel: l10n.aiChatEditUserMessageSubmit,
          cancelLabel: l10n.commonCancel,
          // Treat as destructive — saving discards the existing AI
          // reply (+ any later turns) before re-running the prompt.
          destructive: true,
          onSubmit: () => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.aiChatEditUserMessageWarning,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: controller),
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    if (result == message.content.trim()) return;
    if (!context.mounted) return;
    await ref
        .read(chatControllerProvider(sessionId).notifier)
        .editAndResend(messageId: message.id, newContent: result);
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.sessionId,
    required this.message,
    this.onReplyChip,
    this.invocationIntent,
    this.isLastAssistant = false,
    this.suggestCannedReplies = true,
  });

  final String sessionId;
  final ChatMessage message;
  final void Function(String chip)? onReplyChip;
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
              Icon(FLucideIcons.circleAlert, size: AppIconSizes.sm, color: colors.destructive),
              const SizedBox(width: 6),
              Text(
                l10n.aiChatSemanticsAssistantError,
                style: context.theme.typography.xs.copyWith(
                  color: colors.destructive,
                  fontWeight: FontWeight.w600,
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
        ..._buildInterleavedBlocks(
          context: context,
          textColor: textColor,
          isStreaming: isStreaming,
        ),
        if (errorMessage != null && errorMessage.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            errorMessage,
            style: context.theme.typography.xs.copyWith(
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
          AiTransparencyBadge(messageId: message.id),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(
          color: _isError
              ? colors.destructive.withValues(alpha: 0.55)
              : colors.border,
          width: _isError ? 1.5 : 1,
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
          const SizedBox(width: 8),
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
        return DecisionCard(
          request: request,
          interactive: isLastAssistant && onReplyChip != null,
          onSelect: (reply) => onReplyChip?.call(reply),
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
/// invocation without an output is the one currently being awaited.
String? _findPendingToolName(List<ToolInvocation> tools) {
  for (var i = tools.length - 1; i >= 0; i--) {
    if (tools[i].output == null) return tools[i].name;
  }
  return null;
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
            const SizedBox(width: 6),
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
            const SizedBox(width: 2),
            _TypingDots(color: AiTone.active(context).withValues(alpha: 0.7)),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(
            l10n.aiChatThinking,
            style: context.theme.typography.sm.copyWith(
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }
    final base = context.theme.typography.sm.copyWith(
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
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

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
              if (i > 0) const SizedBox(width: 4),
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
        width: 6,
        height: 6,
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
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

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
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Slim, muted hairline + label + "Continue" affordance shown at the
/// bottom of an assistant bubble when [ChatMessage.stopReason] indicates
/// the reply is incomplete (max_tokens, refusal, tool-budget exhausted,
/// connection drop, …).
///
/// The footer is purely a UX signal — the message itself is already
/// persisted as `complete`. Tapping "Continue" sends a hidden user turn
/// asking the model to pick up where it left off.
class _TruncationFooter extends ConsumerWidget {
  const _TruncationFooter({required this.sessionId, required this.reason});

  final String sessionId;
  final ChatStopReason reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muted = context.theme.colors.mutedForeground;

    final canContinue = switch (reason) {
      ChatStopReason.maxTokens ||
      ChatStopReason.toolUse ||
      ChatStopReason.error ||
      ChatStopReason.unknown => true,
      ChatStopReason.refusal || ChatStopReason.endTurn => false,
    };
    final label = switch (reason) {
      ChatStopReason.maxTokens => l10n.aiChatTruncatedMaxTokens,
      ChatStopReason.toolUse => l10n.aiChatTruncatedToolBudget,
      ChatStopReason.refusal => l10n.aiChatTruncatedRefusal,
      ChatStopReason.error => l10n.aiChatTruncatedNetwork,
      ChatStopReason.unknown => l10n.aiChatTruncatedUnknown,
      ChatStopReason.endTurn => '',
    };

    final turn = ref.watch(chatControllerProvider(sessionId));

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            color: context.theme.colors.border.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              Icon(FLucideIcons.scissors, size: AppIconSizes.xs, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.xs.copyWith(color: muted),
                ),
              ),
              if (canContinue)
                _ContinueButton(
                  enabled: !turn.isBusy,
                  label: l10n.aiChatTruncatedContinue,
                  onPressed: () {
                    ref
                        .read(chatControllerProvider(sessionId).notifier)
                        .send(l10n.aiChatTruncatedContinuePrompt);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return FTappable(
      onPress: enabled ? onPressed : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.theme.typography.xs.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(FLucideIcons.arrowRight, size: AppIconSizes.xs, color: color),
          ],
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
    final labelStyle = context.theme.typography.xs.copyWith(
      color: colors.mutedForeground,
      fontWeight: FontWeight.w600,
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
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? FLucideIcons.chevronUp
                      : FLucideIcons.chevronDown,
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
              baseStyle: context.theme.typography.xs.copyWith(
                height: 1.45,
                color: colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // The assistant identity glyph is a framed
    // [AiSparkle]. No ad-hoc `secondary` hue — surface tint + hairline
    // only (AiTone), per core/ai/visual §5.8.
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AiTone.surfaceTint(context),
        border: Border.all(color: AiTone.outline(context), width: 1),
      ),
      alignment: Alignment.center,
      child: const AiSparkle(size: AppIconSizes.sm),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Center(
        child: Semantics(
          container: true,
          label: l10n.aiChatSemanticsSystemNotice,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s4),
            decoration: BoxDecoration(
              color: context.theme.colors.secondary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              text,
              style: context.theme.typography.xs2.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reply chip row under completed assistant turns.
/// Now backed by [AiPill] so chips share the capsule's
/// visual language. Up to 3 chips sourced from `suggestReplyChips`.
class _ReplyChips extends StatelessWidget {
  const _ReplyChips({
    required this.toolNames,
    required this.invocationIntent,
    required this.onTap,
  });

  final Set<String> toolNames;
  final String? invocationIntent;
  final void Function(String chip) onTap;

  @override
  Widget build(BuildContext context) {
    final ids = suggestReplyChips(
      invocationIntent: invocationIntent,
      turnTools: toolNames,
    );
    if (ids.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // The localized phrase is both the chip label and the user turn
    // sent on tap — the model sees natural language, never the id.
    final labels = [for (final id in ids) localizedReplyChip(l10n, id)];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels)
          AiPill(label: label, onTap: () => onTap(label)),
      ],
    );
  }
}


/// Inline copy / regenerate row shown under a completed (or errored)
/// assistant turn. Kept low-contrast on purpose — these are escape
/// hatches users only reach for when something is off, not primary
/// affordances competing with the reply chips below them.
class _AssistantActions extends ConsumerWidget {
  const _AssistantActions({
    required this.sessionId,
    required this.message,
    required this.canRegenerate,
  });

  final String sessionId;
  final ChatMessage message;

  /// True when this row sits under the trailing assistant message,
  /// which is the only time regenerate is safe (mid-thread regenerate
  /// would silently drop every follow-up turn).
  final bool canRegenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canCopy = message.content.trim().isNotEmpty;
    if (!canCopy && !canRegenerate) return const SizedBox.shrink();
    final turn = ref.watch(chatControllerProvider(sessionId));
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        if (canCopy)
          _ActionButton(
            icon: FLucideIcons.copy,
            label: l10n.aiChatMessageCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.content));
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(context);
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(l10n.aiChatMessageCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        if (canRegenerate)
          _ActionButton(
            icon: FLucideIcons.refreshCw,
            label: l10n.aiChatMessageRegenerate,
            // Disable while a turn is in flight so a double-tap doesn't
            // race against the on-going stream.
            onPressed: turn.isBusy
                ? null
                : () {
                    ref
                        .read(chatControllerProvider(sessionId).notifier)
                        .regenerateLast();
                  },
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? context.theme.colors.mutedForeground
        : context.theme.colors.mutedForeground.withValues(alpha: 0.4);
    return FTappable(
      onPress: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: AppSpacing.s4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.xs, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.theme.typography.xs.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
