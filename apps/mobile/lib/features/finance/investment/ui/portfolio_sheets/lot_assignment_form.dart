part of '../investment_portfolio_sheets.dart';

class _PortfolioLotAssignmentLoader extends ConsumerWidget {
  const _PortfolioLotAssignmentLoader({this.preferredGroupId});

  final String? preferredGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final assignments = ref.watch(portfolioCapitalAssignmentsProvider);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    final lots = ref.watch(allInvestmentLotsProvider);
    final assets = ref.watch(allAssetsStreamProvider);
    if (portfolios.hasError ||
        assignments.hasError ||
        groups.hasError ||
        lots.hasError ||
        assets.hasError) {
      final failed = [
        portfolios,
        assignments,
        groups,
        lots,
        assets,
      ].firstWhere((value) => value.hasError);
      return AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          failed.error!,
          stackTrace: failed.stackTrace,
          operation: 'load portfolio lot assignments',
        ),
      );
    }
    if (!portfolios.hasValue ||
        !assignments.hasValue ||
        !groups.hasValue ||
        !lots.hasValue ||
        !assets.hasValue) {
      return const Center(child: FCircularProgress());
    }
    return _PortfolioLotAssignmentForm(
      key: ValueKey(
        Object.hash(
          portfolios.value,
          assignments.value,
          groups.value,
          lots.value,
          assets.value,
        ),
      ),
      portfolios: portfolios.requireValue,
      assignments: assignments.requireValue,
      groups: groups.requireValue.where((group) => !group.archived).toList(),
      lots: lots.requireValue.where((lot) => !lot.isClosed).toList(),
      assetLabels: {
        for (final asset in assets.requireValue)
          asset.id: asset.name?.trim().isNotEmpty == true
              ? asset.name!.trim()
              : asset.symbol,
      },
      preferredGroupId: preferredGroupId,
    );
  }
}

class _PortfolioLotAssignmentForm extends ConsumerStatefulWidget {
  const _PortfolioLotAssignmentForm({
    super.key,
    required this.portfolios,
    required this.assignments,
    required this.groups,
    required this.lots,
    required this.assetLabels,
    required this.preferredGroupId,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioCapitalAssignment> assignments;
  final List<PortfolioRebalanceGroup> groups;
  final List<Lot> lots;
  final Map<String, String> assetLabels;
  final String? preferredGroupId;

  @override
  ConsumerState<_PortfolioLotAssignmentForm> createState() =>
      _PortfolioLotAssignmentFormState();
}

class _PortfolioLotAssignmentFormState
    extends ConsumerState<_PortfolioLotAssignmentForm> {
  late final Map<String, String> _initial;
  late final Map<String, String> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initial = {
      for (final assignment in widget.assignments)
        if (assignment.sourceKind == PortfolioCapitalSourceKind.lot &&
            assignment.isWholeLot)
          assignment.sourceId: assignment.rebalanceGroupId,
    };
    _selected = {for (final lot in widget.lots) lot.id: _initial[lot.id] ?? ''};
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      for (final entry in _selected.entries) {
        if (entry.value == (_initial[entry.key] ?? '')) continue;
        final prior = widget.assignments
            .where(
              (assignment) =>
                  assignment.sourceKind == PortfolioCapitalSourceKind.lot &&
                  assignment.sourceId == entry.key &&
                  assignment.isWholeLot,
            )
            .firstOrNull;
        if (prior != null) {
          if (entry.value.isEmpty) {
            await repository.unassignCapital(prior);
            continue;
          }
          final group = widget.groups.firstWhere(
            (candidate) => candidate.id == entry.value,
          );
          await repository.moveCapitalAssignment(
            assignment: prior,
            portfolioId: group.portfolioId,
            rebalanceGroupId: group.id,
          );
          continue;
        }
        if (entry.value.isNotEmpty) {
          final group = widget.groups.firstWhere(
            (candidate) => candidate.id == entry.value,
          );
          await repository.assignWholeLot(
            lotId: entry.key,
            portfolioId: group.portfolioId,
            rebalanceGroupId: group.id,
          );
        }
      }
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).portfolioAssignmentSaved,
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.portfolios.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.layers,
        title: l10n.portfolioNoPortfolios,
        action: FButton(
          onPress: () => showInvestmentPortfolioFormSheet(context),
          child: Text(l10n.portfolioCreateTitle),
        ),
      );
    }
    if (widget.lots.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.packageOpen,
        title: l10n.portfolioHubEmpty,
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            Navigator.of(context).maybePop();
            context.push(FinanceRoutes.tradeEntry);
          },
          child: Text(l10n.tradeEntryAppBarTitle),
        ),
      );
    }
    final portfolioNames = {
      for (final portfolio in widget.portfolios) portfolio.id: portfolio.name,
    };
    final orderedGroups = [...widget.groups]
      ..sort((a, b) {
        if (a.id == widget.preferredGroupId) return -1;
        if (b.id == widget.preferredGroupId) return 1;
        return 0;
      });
    final labels = {
      for (final group in orderedGroups)
        group.id:
            '${portfolioNames[group.portfolioId] ?? group.portfolioId} · ${group.name}',
    };
    final partialLotIds = {
      for (final assignment in widget.assignments)
        if (assignment.sourceKind == PortfolioCapitalSourceKind.lot &&
            !assignment.isWholeLot)
          assignment.sourceId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lot in widget.lots) ...[
          if (partialLotIds.contains(lot.id))
            _PartialLotAssignments(
              lot: lot,
              label: widget.assetLabels[lot.assetId] ?? lot.assetId,
              assignments: widget.assignments
                  .where(
                    (assignment) =>
                        assignment.sourceKind ==
                            PortfolioCapitalSourceKind.lot &&
                        assignment.sourceId == lot.id &&
                        !assignment.isWholeLot,
                  )
                  .toList(growable: false),
              labels: labels,
              busy: _busy,
              onMove: (assignment) => _movePartialAssignment(
                assignment: assignment,
                lot: lot,
                labels: labels,
              ),
              onRemove: _removePartialAssignment,
              onAdd: (remaining) => _addPartialAssignment(
                lot: lot,
                remaining: remaining,
                labels: labels,
              ),
            )
          else
            FSelect<String>.rich(
              format: (id) => id.isEmpty
                  ? l10n.portfolioUnassigned
                  : labels[id] ?? l10n.portfolioUnassigned,
              control: FSelectControl<String>.lifted(
                value: _selected[lot.id] ?? '',
                onChange: (value) {
                  if (_busy) return;
                  setState(() => _selected[lot.id] = value ?? '');
                },
              ),
              enabled: !_busy,
              label: Text(widget.assetLabels[lot.assetId] ?? lot.assetId),
              description: Text(
                '${lot.remainingQuantity} · ${lot.openedAt.toLocal().toIso8601String().substring(0, 10)}',
              ),
              children: [
                FSelectItem<String>(
                  value: '',
                  title: Text(l10n.portfolioUnassigned),
                ),
                for (final group in orderedGroups)
                  FSelectItem<String>(
                    value: group.id,
                    title: Text(labels[group.id]!),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.s12),
        ],
        const SizedBox(height: AppSpacing.s8),
        AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave),
      ],
    );
  }

  Future<void> _movePartialAssignment({
    required PortfolioCapitalAssignment assignment,
    required Lot lot,
    required Map<String, String> labels,
  }) async {
    var selectedGroupId = assignment.rebalanceGroupId;
    final targetGroupId = await showAppSheet<String>(
      context: context,
      title: AppLocalizations.of(context).portfolioCapitalAssignmentTitle,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FSelect<String>.rich(
              format: (id) => labels[id] ?? id,
              control: FSelectControl<String>.lifted(
                value: selectedGroupId,
                onChange: (value) {
                  if (value == null) return;
                  setSheetState(() => selectedGroupId = value);
                },
              ),
              label: Text(AppLocalizations.of(context).portfolioGroupNameLabel),
              children: [
                for (final group in widget.groups)
                  FSelectItem<String>(
                    value: group.id,
                    title: Text(labels[group.id]!),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            FButton(
              onPress: selectedGroupId == assignment.rebalanceGroupId
                  ? null
                  : () => Navigator.of(sheetContext).pop(selectedGroupId),
              child: Text(AppLocalizations.of(context).commonSave),
            ),
          ],
        ),
      ),
    );
    if (targetGroupId == null || !mounted) return;
    final group = widget.groups.firstWhere((item) => item.id == targetGroupId);
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.moveCapitalAssignment(
        assignment: assignment,
        portfolioId: group.portfolioId,
        rebalanceGroupId: group.id,
        sourceCapacity: lot.remainingQuantity,
      );
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPartialAssignment({
    required Lot lot,
    required Decimal remaining,
    required Map<String, String> labels,
  }) async {
    final quantityController = TextEditingController(
      text: remaining.toString(),
    );
    var groupId =
        widget.preferredGroupId ?? widget.groups.firstOrNull?.id ?? '';
    try {
      final result = await showAppSheet<({String groupId, Decimal quantity})>(
        context: context,
        title: AppLocalizations.of(context).portfolioAssignLotsTitle,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FSelect<String>.rich(
                format: (id) => labels[id] ?? id,
                control: FSelectControl<String>.lifted(
                  value: groupId,
                  onChange: (value) {
                    if (value == null) return;
                    setSheetState(() => groupId = value);
                  },
                ),
                label: Text(
                  AppLocalizations.of(context).portfolioGroupNameLabel,
                ),
                children: [
                  for (final group in widget.groups)
                    FSelectItem<String>(
                      value: group.id,
                      title: Text(labels[group.id]!),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(
                  controller: quantityController,
                ),
                label: Text(
                  AppLocalizations.of(context).tradeEntryQuantityLabel,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              FButton(
                onPress: () {
                  final quantity = Decimal.tryParse(
                    quantityController.text.trim(),
                  );
                  if (groupId.isEmpty ||
                      quantity == null ||
                      quantity <= Decimal.zero ||
                      quantity > remaining) {
                    AppMessenger.show(
                      context,
                      ToastKind.error,
                      AppLocalizations.of(context).portfolioSaveFailed,
                    );
                    return;
                  }
                  Navigator.of(
                    sheetContext,
                  ).pop((groupId: groupId, quantity: quantity));
                },
                child: Text(AppLocalizations.of(context).commonSave),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      final group = widget.groups.firstWhere(
        (item) => item.id == result.groupId,
      );
      setState(() => _busy = true);
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.assignLotQuantity(
        lotId: lot.id,
        quantity: result.quantity,
        availableQuantity: lot.remainingQuantity,
        portfolioId: group.portfolioId,
        rebalanceGroupId: group.id,
      );
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    } finally {
      quantityController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePartialAssignment(
    PortfolioCapitalAssignment assignment,
  ) async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.unassignCapital(assignment);
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PartialLotAssignments extends StatelessWidget {
  const _PartialLotAssignments({
    required this.lot,
    required this.label,
    required this.assignments,
    required this.labels,
    required this.busy,
    required this.onMove,
    required this.onRemove,
    required this.onAdd,
  });

  final Lot lot;
  final String label;
  final List<PortfolioCapitalAssignment> assignments;
  final Map<String, String> labels;
  final bool busy;
  final ValueChanged<PortfolioCapitalAssignment> onMove;
  final ValueChanged<PortfolioCapitalAssignment> onRemove;
  final ValueChanged<Decimal> onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assigned = assignments.fold<Decimal>(
      Decimal.zero,
      (sum, assignment) => sum + (assignment.quantity ?? Decimal.zero),
    );
    final remaining = lot.remainingQuantity - assigned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.theme.typography.body.sm),
        const SizedBox(height: AppSpacing.s2),
        Text(
          '${lot.remainingQuantity} · ${lot.openedAt.toLocal().toIso8601String().substring(0, 10)}',
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < assignments.length; index++) ...[
                FTile(
                  prefix: const Icon(FLucideIcons.split),
                  title: Text(
                    labels[assignments[index].rebalanceGroupId] ??
                        assignments[index].rebalanceGroupId,
                  ),
                  subtitle: Text(
                    '${l10n.tradeEntryQuantityLabel} ${assignments[index].quantity}',
                  ),
                  onPress: busy ? null : () => onMove(assignments[index]),
                  suffix: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: busy ? null : () => onRemove(assignments[index]),
                    child: const Icon(FLucideIcons.x),
                  ),
                ),
                if (index != assignments.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
        if (remaining > Decimal.zero) ...[
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: busy ? null : () => onAdd(remaining),
            prefix: const Icon(FLucideIcons.plus),
            child: Text(
              '${l10n.portfolioAssignLotsTitle} · ${l10n.tradeEntryQuantityLabel} $remaining',
            ),
          ),
        ],
      ],
    );
  }
}
