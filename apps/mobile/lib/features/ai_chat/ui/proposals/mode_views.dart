part of 'propose_card.dart';

class _ExpandedView extends ConsumerWidget {
  const _ExpandedView({
    required this.plan,
    required this.applyState,
    required this.overrides,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final Map<String, Object?>? overrides;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    final isErrored = applyState.status == ProposalApplyStatus.errored;
    final summary = overrides == null
        ? plan.summaryZh
        : l10n.aiChatProposalSummaryEdited(plan.summaryZh);

    // Heavy tier: SoftCard with clear primary CTA hierarchy.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: SoftCard.raised(
        padding: const EdgeInsets.all(AppSpacing.s12),
        borderRadius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconFor(registry, plan.kind),
                  size: AppIconSizes.sm,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    l10n.aiChatProposalPendingHeader(
                      proposalKindLabel(l10n, registry, plan.kind),
                    ),
                    style: AiType.meta(context),
                  ),
                ),
                if (isApplying)
                  const SizedBox(
                    width: AppIconSizes.sm,
                    height: AppIconSizes.sm,
                    child: FCircularProgress(),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              summary,
              style: context.rowTitleStyle.copyWith(color: colors.foreground),
            ),
            const SizedBox(height: AppSpacing.s10),
            ProposalPayloadDetails(plan: plan, overrides: overrides),
            if (plan.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s10),
              _WarningCallout(warnings: plan.warnings),
            ],
            if (isErrored && applyState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                l10n.aiChatProposalFailure(applyState.errorMessage!),
                style: context.captionStyle.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s14),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.primary,
                    onPress: isApplying ? null : onConfirm,
                    prefix: isApplying
                        ? null
                        : const Icon(FLucideIcons.check, size: AppIconSizes.xs),
                    child: Text(
                      isApplying
                          ? l10n.aiChatProposalApplying
                          : l10n.aiChatProposalConfirm,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: isApplying ? null : onEdit,
                  prefix: const Icon(
                    FLucideIcons.pencil,
                    size: AppIconSizes.xs,
                  ),
                  child: Text(l10n.aiChatProposalEdit),
                ),
                const SizedBox(width: AppSpacing.s4),
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: isApplying ? null : onCancel,
                  prefix: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
                  child: Text(l10n.commonCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// InteractionMode.oneTap surface.
//
// Reserved for low-risk, easily-undoable proposals (memo edits, tag
// applies, category sets, small expense entries). The expanded diff
// preview is overkill for these — one tap should be enough. Errors
// still fall back to the full ExpandedView wording so users can read
// what went wrong.
// ───────────────────────────────────────────────────────────────────────────
class _OneTapView extends ConsumerWidget {
  const _OneTapView({
    required this.plan,
    required this.applyState,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  bool get _isApplying => applyState.status == ProposalApplyStatus.applying;
  bool get _isErrored => applyState.status == ProposalApplyStatus.errored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    final colors = context.theme.colors;
    // Light tier: compact SoftCard — one primary confirm + quiet secondaries.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: SoftCard.flat(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s12,
          AppSpacing.s10,
          AppSpacing.s10,
          AppSpacing.s10,
        ),
        borderRadius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconFor(registry, plan.kind),
                  size: AppIconSizes.xs,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    proposalKindLabel(l10n, registry, plan.kind),
                    style: AiType.meta(context),
                  ),
                ),
                if (_isApplying)
                  const SizedBox(
                    width: AppIconSizes.xs,
                    height: AppIconSizes.xs,
                    child: FCircularProgress(size: .xs),
                  )
                else
                  FButton(
                    variant: FButtonVariant.primary,
                    size: FButtonSizeVariant.sm,
                    mainAxisSize: MainAxisSize.min,
                    onPress: onConfirm,
                    child: Text(l10n.aiChatProposalConfirm),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              plan.summaryZh,
              style: AiType.body(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isErrored && applyState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.s6),
              Text(
                applyState.errorMessage!,
                style: AiType.meta(
                  context,
                ).copyWith(color: AiTone.error(context)),
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                FButton(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: _isApplying ? null : onEdit,
                  child: Text(l10n.aiChatProposalEdit),
                ),
                FButton(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: _isApplying ? null : onCancel,
                  child: Text(l10n.commonCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// InteractionMode.typed surface.
//
// User must type a literal "确认" (or the proposal amount in future
// revisions) before Apply is enabled. Reserved for broker_order /
// bulk_delete-class proposals that no current backend tool generates —
// the view exists so the framework is ready when those tools ship.
// ───────────────────────────────────────────────────────────────────────────
class _TypedConfirmView extends StatefulWidget {
  const _TypedConfirmView({
    required this.plan,
    required this.applyState,
    required this.overrides,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final Map<String, Object?>? overrides;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  State<_TypedConfirmView> createState() => _TypedConfirmViewState();
}

class _TypedConfirmViewState extends State<_TypedConfirmView> {
  final _controller = TextEditingController();
  static const _confirmToken = '确认';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _matches => _controller.text.trim() == _confirmToken;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Reuse the expanded view's diff body, but disable its
        // Confirm button by swapping in a typed-confirm callback that
        // refuses unless the token matches.
        _ExpandedView(
          plan: widget.plan,
          applyState: widget.applyState,
          overrides: widget.overrides,
          onConfirm: () {
            if (_matches) widget.onConfirm();
          },
          onCancel: widget.onCancel,
          onEdit: widget.onEdit,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s12,
            AppSpacing.s8,
            AppSpacing.s12,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiChatProposalConfirmTokenWarning(_confirmToken),
                style: AiType.meta(
                  context,
                ).copyWith(color: AiTone.error(context)),
              ),
              const SizedBox(height: AppSpacing.s6),
              FTextField(
                control: FTextFieldControl.managed(controller: _controller),
                hint: _confirmToken,
              ),
              if (!_matches)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s4),
                  child: Text(
                    l10n.aiChatProposalConfirmTokenPending(_confirmToken),
                    style: AiType.meta(context),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s4),
                  child: Text(
                    l10n.aiChatProposalConfirm,
                    style: AiType.meta(
                      context,
                    ).copyWith(color: AiTone.active(context)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
