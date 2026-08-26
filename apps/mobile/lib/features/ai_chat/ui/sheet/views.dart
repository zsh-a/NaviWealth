part of 'ai_sheet.dart';

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.title, this.onExpand, this.onNew});
  final String title;
  final VoidCallback? onExpand;

  /// Start a fresh conversation (clears the resumed thread from view).
  /// Null while no session is resolved or a new one is being created.
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          const AiSparkle(size: AppIconSizes.sm),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: Text(title, style: AiType.title(context))),
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.aiChatSheetNewTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onNew,
              child: const Icon(FLucideIcons.squarePen, size: AppIconSizes.md),
            ),
          ),
          FTooltip(
            tipBuilder: (_, _) => Text(l10n.aiChatSheetExpandTooltip),
            child: FButton.icon(
              variant: FButtonVariant.ghost,
              onPress: onExpand,
              child: const Icon(FLucideIcons.maximize, size: AppIconSizes.md),
            ),
          ),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => Navigator.of(context).pop(),
            child: const Icon(FLucideIcons.x, size: AppIconSizes.md),
          ),
        ],
      ),
    );
  }
}

class _ConversationComposer extends ConsumerWidget {
  const _ConversationComposer({required this.sessionId, this.prefill});
  final String sessionId;
  final String? prefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(chatControllerProvider(sessionId));
    final routeCtx = ref.watch(aiContextProvider);
    final systemContext = routeCtx.toSystemContext();
    return ChatComposer(
      sessionId: sessionId,
      isStreaming: turn.isStreaming,
      isVoiceActive: turn.voiceActive,
      canStartVoice: turn.canStartVoice,
      voiceCapabilities: turn.voiceCapabilities,
      voiceCapsuleVisible: turn.voiceCapsuleVisible,
      voicePhase: turn.voicePhase,
      voiceTranscript: turn.voiceTranscript,
      voiceErrorCode: turn.voiceErrorCode,
      voiceOutputErrorCode: turn.voiceOutputErrorCode,
      voiceInputLane: turn.voiceInputLane,
      voiceOutputLane: turn.voiceOutputLane,
      onStartVoice: () => ref
          .read(chatControllerProvider(sessionId).notifier)
          .startVoice(systemContext: systemContext),
      onStopVoice: () =>
          ref.read(chatControllerProvider(sessionId).notifier).stopVoice(),
      onCancelVoice: () =>
          ref.read(chatControllerProvider(sessionId).notifier).cancelVoice(),
      initialText: prefill,
      onSend: (text) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .send(text, systemContext: systemContext);
      },
      onSendWithOrigin: (text, origin) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .send(
              text,
              systemContext: systemContext,
              turnMetadata: ChatTurnMetadata(inputOrigin: origin),
            );
      },
      onEditResend: (messageId, text) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .editAndResend(
              messageId: messageId,
              newContent: text,
              systemContext: systemContext,
            );
      },
      onCancel: () {
        ref.read(chatControllerProvider(sessionId).notifier).cancel();
      },
    );
  }
}

class _InvocationHeader extends ConsumerWidget {
  const _InvocationHeader({required this.invocation, this.objectLabel});
  final AiIntentInvocation invocation;
  final String? objectLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desc = ref.watch(intentCatalogProvider).lookup(invocation.intent);
    final l10n = AppLocalizations.of(context);
    // Single inline header row: sparkle + intent label + middot +
    // object label, so context stays visible while the body scrolls.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s4,
        AppSpacing.s20,
        AppSpacing.s12,
      ),
      child: Row(
        children: [
          const AiSparkle(),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: localizedIntentLabel(l10n, desc),
                    style: AiType.label(context),
                  ),
                  if (objectLabel != null) ...[
                    TextSpan(text: '  ·  ', style: AiType.meta(context)),
                    TextSpan(text: objectLabel!, style: AiType.meta(context)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shape that materialises into the first assistant turn —
/// three muted bars sized like a chat bubble, pulsing subtly.
class _BodySkeleton extends StatefulWidget {
  const _BodySkeleton({this.animated = true});

  final bool animated;

  @override
  State<_BodySkeleton> createState() => _BodySkeletonState();
}

class _BodySkeletonState extends State<_BodySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    _ctrl.duration = AppMotionPolicy.duration(
      context,
      Motion.shimmerCycle,
      role: AppMotionRole.decorative,
    );
    final shouldRun =
        widget.animated &&
        AppMotionPolicy.isEnabled(context, role: AppMotionRole.decorative);
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (shouldRun) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl
        ..stop()
        ..value = widget.animated ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(_BodySkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) return;
    _syncAnimation();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = widget.animated ? _ctrl.value : 0.0;
          // Lerp between 0.35 and 0.65 alpha — barely perceptible.
          final alpha = 0.35 + 0.30 * t;
          final color = AiTone.surfaceTint(context).withValues(alpha: alpha);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color, widthFactor: 0.85),
              const SizedBox(height: AppSpacing.s8),
              _bar(color, widthFactor: 0.65),
              const SizedBox(height: AppSpacing.s8),
              _bar(color, widthFactor: 0.45),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(Color color, {required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onExpand, required this.onDismiss});
  final VoidCallback onExpand;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: Row(
        children: [
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onDismiss,
            prefix: const Icon(FLucideIcons.x, size: AppIconSizes.sm),
            child: Text(l10n.commonClose),
          ),
          const Spacer(),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onExpand,
            prefix: const Icon(FLucideIcons.maximize, size: AppIconSizes.sm),
            child: Text(l10n.aiChatSheetExpandTooltip),
          ),
        ],
      ),
    );
  }
}

/// Compact empty state for sheet conversation mode — mirrors the full
/// page suggestion list so half-screen AI does not feel like a poorer
/// surface.
class _SheetEmptyConversation extends ConsumerWidget {
  const _SheetEmptyConversation({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final summary = ref.watch(aiContextSummaryProvider)(l10n);
    final suggestions = _sheetSuggestions(l10n, summary);
    final systemContext = ref.watch(aiContextProvider).toSystemContext();

    void send(String text) {
      ref
          .read(chatControllerProvider(sessionId).notifier)
          .send(text, systemContext: systemContext);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      children: [
        Text(
          l10n.aiChatEmptyTitle,
          textAlign: TextAlign.center,
          style: context.rowTitleStyle.copyWith(color: colors.foreground),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(
          l10n.aiChatSheetEmpty,
          textAlign: TextAlign.center,
          style: context.captionStyle,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          for (var i = 0; i < suggestions.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            AppTappable(
              onPress: () => send(suggestions[i].$1),
              child: SoftCard.flat(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s10,
                ),
                borderRadius: AppRadius.md,
                child: Row(
                  children: [
                    Icon(
                      suggestions[i].$2,
                      size: AppIconSizes.sm,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        suggestions[i].$1,
                        style: context.theme.typography.body.sm,
                      ),
                    ),
                    Icon(
                      FLucideIcons.chevronRight,
                      size: AppIconSizes.xs,
                      color: colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

List<(String, IconData)> _sheetSuggestions(
  AppLocalizations l10n,
  AiContextSummary s,
) {
  final out = <(String, IconData)>[];
  for (final fact in s.facts) {
    final suggestion = fact.suggestion;
    if (suggestion != null) out.add((suggestion, fact.icon));
  }
  if (out.length > 2) out.removeRange(2, out.length);
  final defaults = <(String, IconData)>[
    (l10n.aiChatEmptySuggestion1, FLucideIcons.calendar),
    (l10n.aiChatEmptySuggestion2, FLucideIcons.shield),
    (l10n.aiChatEmptySuggestion3, FLucideIcons.chartPie),
  ];
  final existing = {for (final s in out) s.$1};
  for (final d in defaults) {
    if (out.length >= 3) break;
    if (existing.contains(d.$1)) continue;
    out.add(d);
  }
  return out;
}
