part of 'message_bubble.dart';

/// Slim, muted hairline + label + "Continue" affordance shown at the
/// bottom of an assistant bubble when [ChatMessage.stopReason] indicates
/// the reply is incomplete.
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
                    final systemContext = ref
                        .read(aiContextProvider)
                        .toSystemContext();
                    ref
                        .read(chatControllerProvider(sessionId).notifier)
                        .send(
                          l10n.aiChatTruncatedContinuePrompt,
                          systemContext: systemContext,
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
    final color = enabled
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return AppTappable(
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

/// Icon-only copy / regenerate / transparency under a completed assistant
/// turn. Labels live in tooltips so the timeline stays quiet.
class _AssistantActions extends ConsumerWidget {
  const _AssistantActions({
    required this.sessionId,
    required this.message,
    required this.canRegenerate,
  });

  final String sessionId;
  final ChatMessage message;
  final bool canRegenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canCopy = message.content.trim().isNotEmpty;
    if (!canCopy && !canRegenerate) return const SizedBox.shrink();
    final turn = ref.watch(chatControllerProvider(sessionId));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canCopy)
          _CopyIconAction(
            tooltip: l10n.aiChatMessageCopy,
            copiedTooltip: l10n.aiChatMessageCopied,
            text: message.content,
          ),
        if (canRegenerate)
          _IconAction(
            icon: FLucideIcons.refreshCw,
            tooltip: l10n.aiChatMessageRegenerate,
            onPressed: turn.isBusy
                ? null
                : () {
                    ref
                        .read(chatControllerProvider(sessionId).notifier)
                        .regenerateLast();
                  },
          ),
        _IconAction(
          icon: FLucideIcons.info,
          tooltip: l10n.aiChatTransparencyOpenDetail,
          onPressed: () => pushFromAiSurface(
            context,
            SettingsRoutes.aiTransparencyDetail(message.id),
          ),
        ),
      ],
    );
  }
}

class _CopyIconAction extends StatefulWidget {
  const _CopyIconAction({
    required this.tooltip,
    required this.copiedTooltip,
    required this.text,
  });

  final String tooltip;
  final String copiedTooltip;
  final String text;

  @override
  State<_CopyIconAction> createState() => _CopyIconActionState();
}

class _CopyIconActionState extends State<_CopyIconAction> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    AppInteraction.signal(AppInteractionIntent.success);
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(Motion.copyFeedback);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _copied
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return FTooltip(
      tipBuilder: (_, _) =>
          Text(_copied ? widget.copiedTooltip : widget.tooltip),
      child: AppTappable(
        onPress: _copy,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: AnimatedSwitcher(
            duration: AppMotionPolicy.duration(context, Motion.fast),
            child: Icon(
              _copied ? FLucideIcons.check : FLucideIcons.copy,
              key: ValueKey(_copied),
              size: AppIconSizes.xs,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? context.theme.colors.mutedForeground
        : context.theme.colors.mutedForeground.withValues(
            alpha: AppOpacity.disabled,
          );
    return FTooltip(
      tipBuilder: (_, _) => Text(tooltip),
      child: AppTappable(
        onPress: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Icon(icon, size: AppIconSizes.xs, color: color),
        ),
      ),
    );
  }
}
