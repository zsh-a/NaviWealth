import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';
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

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.toolCalls.isNotEmpty)
          _ToolCallsSection(
            sessionId: sessionId,
            message: message,
          ),
        if (message.content.isNotEmpty || isStreaming) ...[
          if (message.toolCalls.isNotEmpty)
            const SizedBox(height: Spacing.s8),
          _AssistantBody(
            text: message.content,
            isStreaming: isStreaming,
            textColor: textColor,
          ),
        ],
        if (message.errorMessage != null &&
            message.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: Spacing.s8),
          Text(
            message.errorMessage!,
            style: tt.bodySmall?.copyWith(color: cs.error),
          ),
        ],
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

/// Splits an assistant turn's tool calls into the propose / non-propose
/// halves. Propose calls render as `ProposeCard` with a batch action row
/// when 2+ are still pending; everything else falls through to the
/// generic `ToolInvocationCard` exactly like before.
class _ToolCallsSection extends StatelessWidget {
  const _ToolCallsSection({required this.sessionId, required this.message});

  final String sessionId;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final entries = <_ToolEntry>[];
    final pending =
        <({ToolInvocation invocation, ReadyProposalPlan plan})>[];
    for (final t in message.toolCalls) {
      final isPropose = isProposeTool(t.name);
      final plan = isPropose ? ProposalPlan.tryParse(t.output) : null;
      if (isPropose && plan != null) {
        entries.add(_ToolEntry.propose(t, plan));
        if (plan is ReadyProposalPlan) {
          final state = t.applyState ?? ProposalApplyState.pending;
          if (state.status == ProposalApplyStatus.pending ||
              state.status == ProposalApplyStatus.errored) {
            pending.add((invocation: t, plan: plan));
          }
        }
      } else {
        entries.add(_ToolEntry.generic(t));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending.length >= 2)
          ProposeBatchActions(
            sessionId: sessionId,
            message: message,
            pending: pending,
          ),
        for (final entry in entries)
          entry.plan == null
              ? ToolInvocationCard(invocation: entry.invocation)
              : ProposeCard(
                  sessionId: sessionId,
                  message: message,
                  invocation: entry.invocation,
                  plan: entry.plan!,
                ),
      ],
    );
  }
}

class _ToolEntry {
  _ToolEntry.propose(this.invocation, this.plan);
  _ToolEntry.generic(this.invocation) : plan = null;
  final ToolInvocation invocation;
  final ProposalPlan? plan;
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
