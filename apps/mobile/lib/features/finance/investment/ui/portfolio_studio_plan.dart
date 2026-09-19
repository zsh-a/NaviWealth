part of 'portfolio_hub_page.dart';

enum _PlanValuationStatus { ready, loading, failed, unavailable }

/// Full-page plan workspace. The hub keeps the entry point visible while the
/// plan itself owns the complete create → configure → inspect loop.
class PortfolioPlanPage extends ConsumerStatefulWidget {
  const PortfolioPlanPage({super.key});

  @override
  ConsumerState<PortfolioPlanPage> createState() => _PortfolioPlanPageState();
}

class _PortfolioPlanPageState extends ConsumerState<PortfolioPlanPage> {
  Future<void> _editAllocation() async {
    final l10n = AppLocalizations.of(context);
    try {
      final targets = ref
          .read(activeUniversePortfolioTargetsProvider)
          .requireValue;
      final portfolios =
          ref.read(investmentPortfoliosProvider).value ?? const [];
      if (!targets.any(
        (target) =>
            portfolios.any((portfolio) => portfolio.id == target.portfolioId),
      )) {
        if (!mounted) return;
        AppMessenger.show(context, ToastKind.error, l10n.commonLoadFailed);
        return;
      }
      await showPortfolioAllocationEditor(
        context,
        ref,
        portfolios: portfolios,
        targets: targets,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, error, stackTrace: stackTrace),
      );
    }
  }

  void _retry() {
    ref.invalidate(activeRebalanceUniverseProvider);
    ref.invalidate(activeUniversePortfolioTargetsProvider);
    ref.invalidate(investmentPortfoliosProvider);
    ref.invalidate(portfolioRebalanceGroupsProvider);
    ref.invalidate(allPortfolioGroupSnapshotsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tree = ref.watch(portfolioAllocationTreeProvider);
    final plan = ref.watch(universeRebalancePlanProvider);
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final valuationInputs = <AsyncValue<Object?>>[
      ref.watch(activeRebalanceUniverseProvider),
      ref.watch(activeUniversePortfolioTargetsProvider),
      portfolios,
      ref.watch(portfolioRebalanceGroupsProvider),
      ref.watch(allPortfolioGroupSnapshotsProvider),
    ];
    final valuationStatus = valuationInputs.any((input) => input.hasError)
        ? _PlanValuationStatus.failed
        : valuationInputs.any((input) => input.isLoading)
        ? _PlanValuationStatus.loading
        : plan == null
        ? _PlanValuationStatus.unavailable
        : _PlanValuationStatus.ready;

    return AppPageScaffold(
      title: l10n.portfolioStudioPlanTitle,
      childPad: false,
      child: tree.when(
        loading: () => const _PortfolioHubSkeleton(),
        error: (error, stackTrace) =>
            kDefaultError(context, error, stackTrace, onRetry: _retry),
        data: (allocationTree) => allocationTree == null
            ? AppEmptyState(
                icon: FLucideIcons.layers,
                title: l10n.portfolioStudioPlanEmptyHint,
              )
            : AdaptiveContentFrame(
                maxWidth: AdaptiveMaxWidth.page,
                expandSinglePrimary: true,
                padding: shellTabContentPadding(
                  context,
                  left: AppSpacing.s16,
                  top: AppSpacing.s8,
                  right: AppSpacing.s16,
                  bottom: AppSpacing.s24,
                ),
                primary: ListView(
                  children: [
                    AppGroupedSurface(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: _PortfolioPlanList(
                        valuationStatus: valuationStatus,
                        onRetry: _retry,
                        portfolios: portfolios.value ?? const [],
                        tree: allocationTree,
                        actualWeights: {
                          if (plan != null)
                            for (final item in plan.portfolios)
                              item.portfolio.id:
                                  item.capitalDecision.actualWeight,
                        },
                        onPortfolioSelected: (id) => context.push(
                          FinanceRoutes.wealthPortfolioStudioFor(id),
                        ),
                        onCreate: () =>
                            showInvestmentPortfolioFormSheet(context),
                        onEditAllocation: _editAllocation,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PortfolioPlanActionRail extends StatelessWidget {
  const _PortfolioPlanActionRail({
    required this.needsRebalance,
    required this.onPress,
  });

  final bool needsRebalance;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KeyedSubtree(
      key: const ValueKey('portfolio-plan-action'),
      child: AppGroupedActionList(
        actions: [
          AppGroupedAction(
            icon: needsRebalance
                ? FLucideIcons.triangleAlert
                : FLucideIcons.layers3,
            title: l10n.portfolioStudioPlanTitle,
            subtitle: needsRebalance
                ? l10n.portfolioPlanNeedsRebalance
                : l10n.portfolioPlanEditWeights,
            onPress: onPress,
          ),
        ],
      ),
    );
  }
}

/// Allocation is a comparison task: stable rows, not a horizontal chart rail.
class _PortfolioPlanList extends StatelessWidget {
  const _PortfolioPlanList({
    required this.portfolios,
    required this.tree,
    required this.actualWeights,
    required this.onPortfolioSelected,
    required this.onCreate,
    required this.onEditAllocation,
    required this.valuationStatus,
    required this.onRetry,
  });

  final List<InvestmentPortfolio> portfolios;
  final PortfolioAllocationTree tree;
  final Map<String, double> actualWeights;
  final ValueChanged<String> onPortfolioSelected;
  final VoidCallback onCreate;
  final VoidCallback onEditAllocation;
  final _PlanValuationStatus valuationStatus;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final portfolioById = {for (final item in portfolios) item.id: item};
    final nodes = tree.childrenOf(tree.root.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          nodes.isEmpty
              ? l10n.portfolioStudioPlanEmptyHint
              : l10n.portfolioPlanAllocationHint,
          style: context.captionStyle,
        ),
        if (nodes.isNotEmpty &&
            valuationStatus != _PlanValuationStatus.ready) ...[
          const SizedBox(height: AppSpacing.s8),
          Semantics(
            liveRegion: true,
            child: AppBadge(
              label: switch (valuationStatus) {
                _PlanValuationStatus.loading => l10n.portfolioPlanActualLoading,
                _PlanValuationStatus.failed => l10n.portfolioPlanActualFailed,
                _ => l10n.portfolioPlanActualUnavailable,
              },
              tone: switch (valuationStatus) {
                _PlanValuationStatus.failed => AppBadgeTone.warning,
                _ => AppBadgeTone.neutral,
              },
              size: AppBadgeSize.compact,
              icon: switch (valuationStatus) {
                _PlanValuationStatus.loading => FLucideIcons.loaderCircle,
                _PlanValuationStatus.failed => FLucideIcons.cloudAlert,
                _ => FLucideIcons.info,
              },
            ),
          ),
          if (valuationStatus == _PlanValuationStatus.failed)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FButton(
                variant: FButtonVariant.ghost,
                onPress: onRetry,
                child: Text(l10n.commonRetry),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.s12),
        LayoutBuilder(
          builder: (context, constraints) {
            final create = FButton(
              key: const ValueKey('portfolio-plan-create'),
              variant: nodes.isEmpty
                  ? FButtonVariant.primary
                  : FButtonVariant.ghost,
              onPress: onCreate,
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
              child: Flexible(child: Text(l10n.portfolioCreateTitle)),
            );
            if (nodes.length <= 1) return create;
            final edit = FButton(
              key: const ValueKey('portfolio-plan-allocation'),
              variant: FButtonVariant.primary,
              onPress: onEditAllocation,
              prefix: const Icon(
                FLucideIcons.slidersHorizontal,
                size: AppIconSizes.sm,
              ),
              child: Flexible(child: Text(l10n.portfolioPlanEditWeights)),
            );
            if (constraints.maxWidth <
                320 * MediaQuery.textScalerOf(context).scale(1)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  edit,
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: create,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: edit),
                const SizedBox(width: AppSpacing.s8),
                Expanded(child: create),
              ],
            );
          },
        ),
        if (nodes.isNotEmpty) const SizedBox(height: AppSpacing.s12),
        for (final (index, node) in nodes.indexed) ...[
          if (index > 0) const AppGroupedDivider(),
          _PortfolioPlanRow(
            node: node,
            actual: actualWeights[node.referenceId],
            onPress: portfolioById.containsKey(node.referenceId)
                ? () => onPortfolioSelected(node.referenceId!)
                : null,
          ),
        ],
      ],
    );
  }
}

class _PortfolioPlanRow extends StatelessWidget {
  const _PortfolioPlanRow({
    required this.node,
    required this.actual,
    required this.onPress,
  });

  final AllocationNode node;
  final double? actual;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outsideBand =
        actual != null &&
        (actual! - node.targetWeight).abs() > node.driftBandBps / 10000;
    return AppTappable(
      key: ValueKey('portfolio-plan-row-${node.referenceId}'),
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s16,
          horizontal: AppSpacing.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(node.name, style: context.labelStyle)),
                if (onPress != null) ...[
                  const SizedBox(width: AppSpacing.s8),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.sm,
                    color: context.theme.colors.mutedForeground,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: _PlanWeight(
                    label: l10n.portfolioPlanActualWeightLabel,
                    value: actual == null ? '—' : _studioPercent(actual!),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: _PlanWeight(
                    label: l10n.portfolioPlanTargetWeightLabel,
                    value: '${_studioPercentFromBps(node.targetWeightBps)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s10),
            AnimatedSwitcher(
              duration: AppMotionPolicy.duration(
                context,
                Motion.componentChange,
              ),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey('${actual ?? 'unknown'}:${node.targetWeight}'),
                child: _PlanWeightBar(
                  target: node.targetWeight,
                  actual: actual,
                  drifted: outsideBand,
                ),
              ),
            ),
            if (outsideBand) ...[
              const SizedBox(height: AppSpacing.s8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppBadge(
                  label: actual! > node.targetWeight
                      ? l10n.portfolioPlanAboveTarget(
                          _studioPercentFromBps(
                            ((actual! - node.targetWeight) * 10000)
                                .abs()
                                .round(),
                          ),
                        )
                      : l10n.portfolioPlanBelowTarget(
                          _studioPercentFromBps(
                            ((actual! - node.targetWeight) * 10000)
                                .abs()
                                .round(),
                          ),
                        ),
                  icon: FLucideIcons.triangleAlert,
                  tone: AppBadgeTone.warning,
                  size: AppBadgeSize.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanWeightBar extends StatelessWidget {
  const _PlanWeightBar({
    required this.target,
    required this.actual,
    required this.drifted,
  });

  final double target;
  final double? actual;
  final bool drifted;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final actualColor = drifted
        ? context.appTheme.status.warning.fg
        : colors.primary;
    final targetColor = colors.foreground.withValues(alpha: AppOpacity.muted);
    return ExcludeSemantics(
      child: SizedBox(
        height: AppSpacing.s6,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final targetOffset = constraints.maxWidth * target.clamp(0.0, 1.0);
            final actualWidth =
                constraints.maxWidth * (actual ?? 0).clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.border.withValues(alpha: AppOpacity.subtle),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                if (actual != null)
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: actualWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: actualColor,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                PositionedDirectional(
                  start: targetOffset - AppStroke.accent / 2,
                  top: -AppSpacing.s2,
                  bottom: -AppSpacing.s2,
                  width: AppStroke.accent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: targetColor,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlanWeight extends StatelessWidget {
  const _PlanWeight({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.captionStyle),
      const SizedBox(height: AppSpacing.s2),
      Text(value, style: TypographyTokens.numericBodyStrong),
    ],
  );
}
