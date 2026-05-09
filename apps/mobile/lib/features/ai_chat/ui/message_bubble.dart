import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';
import '../state/chat_controller.dart';
import 'propose_card.dart';
import 'tool_invocation_card.dart';

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
  const MessageBubble({super.key, required this.sessionId, required this.message});

  final String sessionId;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (message.role) {
      ChatRole.system => _SystemNotice(text: message.content),
      ChatRole.user => _UserBubble(message: message),
      ChatRole.assistant ||
      ChatRole.error => _AssistantBubble(
        sessionId: sessionId,
        message: message,
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

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.s12,
                  vertical: Spacing.s8,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radii.rLg,
                    topRight: Radii.rXs,
                    bottomLeft: Radii.rLg,
                    bottomRight: Radii.rLg,
                  ),
                  boxShadow: AppElevations.of(context).level1,
                ),
                child: SelectableText(
                  message.content,
                  style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.sessionId, required this.message});

  final String sessionId;
  final ChatMessage message;

  bool get _isError => message.role == ChatRole.error ||
      message.status == ChatMessageStatus.errored;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final textColor = _isError ? cs.onErrorContainer : cs.onSurface;
    final isStreaming = message.status == ChatMessageStatus.streaming;

    final showTruncation = !isStreaming &&
        message.role == ChatRole.assistant &&
        message.status == ChatMessageStatus.complete &&
        (message.stopReason?.isAbnormal ?? false);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._buildInterleavedBlocks(
          context: context,
          textColor: textColor,
          isStreaming: isStreaming,
        ),
        if (message.errorMessage != null &&
            message.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: Spacing.s8),
          Text(
            message.errorMessage!,
            style: tt.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        if (showTruncation)
          _TruncationFooter(
            sessionId: sessionId,
            reason: message.stopReason!,
          ),
      ],
    );

    final bubble = _isError
        ? Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s12,
              vertical: Spacing.s8,
            ),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radii.rXs,
                topRight: Radii.rLg,
                bottomLeft: Radii.rLg,
                bottomRight: Radii.rLg,
              ),
            ),
            child: body,
          )
        : LiquidGlassCard(
            layer: GlassLayer.tertiary,
            borderRadius: Radii.lg,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.s12,
              vertical: Spacing.s8,
            ),
            child: body,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AssistantAvatar(),
          const SizedBox(width: Spacing.s8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RepaintBoundary(child: bubble),
            ),
          ),
        ],
      ),
    );
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
        blocks.add(const SizedBox(height: Spacing.s8));
      }
    }

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLastSeg = i == segments.length - 1;
      final shouldRenderText = seg.isNotEmpty || (isLastSeg && isStreaming);
      if (shouldRenderText) {
        addGapIfNeeded();
        blocks.add(
          _AssistantBody(
            text: seg,
            isStreaming: isLastSeg && isStreaming,
            textColor: textColor,
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
    return ToolInvocationCard(invocation: invocation);
  }
}

class _AssistantAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.85),
            cs.tertiary.withValues(alpha: 0.85),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: AppElevations.of(context).level1,
      ),
      child: Icon(Icons.auto_awesome, size: 14, color: cs.onPrimary),
    );
  }
}

class _AssistantBody extends StatelessWidget {
  const _AssistantBody({
    required this.text,
    required this.isStreaming,
    required this.textColor,
  });
  final String text;
  final bool isStreaming;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    if (text.isEmpty && isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: Spacing.s8),
          Text(
            l10n.aiChatThinking,
            style: tt.bodyMedium?.copyWith(
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    }
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(text: text, style: tt.bodyMedium?.copyWith(color: textColor)),
          if (isStreaming)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _StreamingCaret(color: textColor),
              ),
            ),
        ],
      ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = cs.onSurfaceVariant;

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
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: Spacing.s6),
          Row(
            children: [
              Icon(Icons.content_cut, size: 14, color: muted),
              const SizedBox(width: Spacing.s6),
              Expanded(
                child: Text(
                  label,
                  style: tt.bodySmall?.copyWith(color: muted),
                ),
              ),
              if (canContinue)
                _ContinueButton(
                  enabled: !turn.isBusy,
                  label: l10n.aiChatTruncatedContinue,
                  onPressed: () {
                    ref
                        .read(chatControllerProvider(sessionId).notifier)
                        .send(
                          l10n.aiChatTruncatedContinuePrompt,
                          staleSyncNotice: l10n.aiChatStaleSyncNotice,
                        );
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = enabled ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s8,
          vertical: Spacing.s2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: tt.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_forward, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s4,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Text(
            text,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
