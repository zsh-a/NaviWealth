part of 'propose_card.dart';

class _CollapsedView extends StatelessWidget {
  const _CollapsedView({
    required this.plan,
    required this.applyState,
    required this.onUndoRequest,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;

  /// Invoked when the user taps the (self-ticking) undo button. `null`
  /// when this state can't be undone at all (already-undone / cancelled
  /// rows). The countdown widget owns the "is the 60s window still
  /// open?" question — we no longer pass a precomputed `onUndo` derived
  /// from `DateTime.now()`, which kept forcing the whole ProposeCard
  /// subtree to rebuild every second.
  final VoidCallback? onUndoRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final Color color;
    final String label;
    switch (applyState.status) {
      case ProposalApplyStatus.applied:
        icon = FLucideIcons.circleCheck;
        color = context.theme.colors.primary;
        label =
            applyState.shortLabel ??
            l10n.aiChatProposalAppliedFallback(plan.summaryZh);
      case ProposalApplyStatus.undone:
        icon = FLucideIcons.undo;
        color = context.theme.colors.mutedForeground;
        label = l10n.aiChatProposalUndoneLabel(plan.summaryZh);
      case ProposalApplyStatus.cancelled:
        icon = FLucideIcons.circleX;
        color = context.theme.colors.mutedForeground;
        label = l10n.aiChatProposalCancelledLabel(plan.summaryZh);
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: color),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.foreground,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onUndoRequest != null &&
                  applyState.status == ProposalApplyStatus.applied &&
                  applyState.appliedAt != null)
                _UndoCountdownButton(
                  appliedAt: applyState.appliedAt!,
                  onUndo: onUndoRequest!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Self-contained 60-second undo button. Owns its own 1-second ticker
/// so the host `_ProposeCardState` no longer has to `setState` (and
/// rebuild every sibling sub-view: warnings, payload rows, …) every
/// second just to refresh a single label.
class _UndoCountdownButton extends StatefulWidget {
  const _UndoCountdownButton({required this.appliedAt, required this.onUndo});

  final DateTime appliedAt;
  final VoidCallback onUndo;

  @override
  State<_UndoCountdownButton> createState() => _UndoCountdownButtonState();
}

class _UndoCountdownButtonState extends State<_UndoCountdownButton> {
  static const int _windowSeconds = 60;
  Timer? _ticker;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _recomputeSecondsLeft();
    if (_secondsLeft > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(_recomputeSecondsLeft);
        if (_secondsLeft <= 0) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    }
  }

  @override
  void didUpdateWidget(_UndoCountdownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appliedAt != widget.appliedAt) {
      _ticker?.cancel();
      _recomputeSecondsLeft();
      if (_secondsLeft > 0) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(_recomputeSecondsLeft);
          if (_secondsLeft <= 0) {
            _ticker?.cancel();
            _ticker = null;
          }
        });
      }
    }
  }

  void _recomputeSecondsLeft() {
    final elapsed = DateTime.now().difference(widget.appliedAt).inSeconds;
    _secondsLeft = _windowSeconds - elapsed;
    if (_secondsLeft < 0) _secondsLeft = 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FButton(
      variant: FButtonVariant.ghost,
      onPress: widget.onUndo,
      prefix: const Icon(FLucideIcons.undo, size: 12),
      child: Text(l10n.aiChatProposalUndoCountdown(_secondsLeft)),
    );
  }
}

class _ClarificationView extends ConsumerWidget {
  const _ClarificationView({required this.plan, required this.sessionId});

  final ClarificationProposalPlan plan;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final turn = ref.watch(chatControllerProvider(sessionId));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: FCard.raw(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.circleHelp,
                    size: AppIconSizes.h18,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    l10n.aiChatProposalNeedsClarificationHeader(
                      proposalKindLabel(l10n, registry, plan.kind),
                    ),
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.foreground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              Text(
                plan.reason,
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.foreground,
                ),
              ),
              if (plan.candidates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.aiChatProposalCandidatesHeading,
                  style: context.microCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                // Tapping a candidate sends its label as the next user
                // turn so the clarification round-trips through the same
                // chat pipeline. Disabled while a turn is in flight
                // (`turn.isBusy`) to avoid stacking duplicate selects.
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  children: [
                    for (final c in plan.candidates)
                      AiPill(
                        label: c.label ?? c.id,
                        onTap: turn.isBusy
                            ? null
                            : () => ref
                                  .read(
                                    chatControllerProvider(sessionId).notifier,
                                  )
                                  .send(c.label ?? c.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Surfaces propose-plan warnings so the user actually notices them
/// before tapping Confirm. Stays within the AiTone discipline (no new
/// warning hue): the visual hook is a surface-tint container + a 2px
/// accent stripe + bolder icon/text, not a saturated yellow.
class _WarningCallout extends StatelessWidget {
  const _WarningCallout({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s10,
        AppSpacing.s8,
        AppSpacing.s10,
        AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: AiTone.surfaceTint(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(
          left: BorderSide(
            color: AiTone.active(
              context,
            ).withValues(alpha: AppOpacity.prominent),
            width: AppStroke.branch,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < warnings.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FLucideIcons.triangleAlert,
                  size: AppIconSizes.sm,
                  color: AiTone.onSurface(context),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    warnings[i],
                    style: context.captionMediumStyle.copyWith(
                      color: AiTone.onSurface(context),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
