part of 'message_bubble.dart';

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
            height: AppStroke.hairline,
            color: context.theme.colors.border.withValues(
              alpha: AppOpacity.scrim,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              Icon(FLucideIcons.scissors, size: AppIconSizes.xs, color: muted),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  label,
                  style: context.captionStyle.copyWith(color: muted),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.captionLabelStyle.copyWith(color: color),
            ),
            const SizedBox(width: AppSpacing.s2),
            Icon(FLucideIcons.arrowRight, size: AppIconSizes.xs, color: color),
          ],
        ),
      ),
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
        border: Border.all(
          color: AiTone.outline(context),
          width: AppStroke.hairline,
        ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: context.theme.colors.secondary.withValues(
                alpha: AppOpacity.prominent,
              ),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(text, style: context.microCaptionStyle),
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
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s6,
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
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s2,
      children: [
        if (canCopy)
          _ActionButton(
            icon: FLucideIcons.copy,
            label: l10n.aiChatMessageCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.content));
              if (!context.mounted) return;
              AppMessenger.show(
                context,
                ToastKind.success,
                l10n.aiChatMessageCopied,
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
        : context.theme.colors.mutedForeground.withValues(
            alpha: AppOpacity.disabled,
          );
    return FTappable(
      onPress: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.xs, color: color),
            const SizedBox(width: AppSpacing.s4),
            Text(label, style: context.captionStyle.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
