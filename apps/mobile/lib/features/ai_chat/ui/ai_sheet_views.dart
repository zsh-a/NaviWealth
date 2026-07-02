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
    return ChatComposer(
      isStreaming: turn.isStreaming,
      initialText: prefill,
      onSend: (text) {
        ref
            .read(chatControllerProvider(sessionId).notifier)
            .send(text, systemContext: routeCtx.toSystemContext());
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
  bool _configured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _ctrl.duration = AiMotion.duration(context, Motion.shimmerCycle);
    if (widget.animated && !reduceMotion) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(_BodySkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) return;
    if (widget.animated) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
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
          borderRadius: BorderRadius.circular(AppRadius.xs),
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
