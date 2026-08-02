import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../rebalance/domain/portfolio_rebalance_group.dart';
import '../../rebalance/domain/rebalance_universe.dart';
import '../data/investment_portfolio_providers.dart';
import '../data/providers.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
import 'portfolio_removal_feedback.dart';
import 'portfolio_strategy_visuals.dart';
import 'removal_transfer_sheet.dart';

Future<bool?> showInvestmentPortfolioFormSheet(
  BuildContext context, {
  InvestmentPortfolio? existing,
}) async {
  final dirty = FormDirtyController();
  try {
    return await showAppFormSheet<bool>(
      context: context,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) =>
          _InvestmentPortfolioForm(existing: existing, dirty: dirty),
    );
  } finally {
    dirty.dispose();
  }
}

Future<void> showPortfolioLotAssignmentSheet(
  BuildContext context, {
  String? preferredGroupId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioAssignLotsTitle,
    subtitle: l10n.portfolioAssignLotsSubtitle,
    builder: (_) =>
        _PortfolioLotAssignmentLoader(preferredGroupId: preferredGroupId),
  );
}

Future<void> showPortfolioCashAssignmentSheet(
  BuildContext context, {
  String? preferredGroupId,
  Decimal? suggestedAmount,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioAssignCashTitle,
    subtitle: l10n.portfolioAssignCashSubtitle,
    builder: (_) => _PortfolioCashAssignmentLoader(
      preferredGroupId: preferredGroupId,
      suggestedAmount: suggestedAmount,
    ),
  );
}

class _InvestmentPortfolioForm extends ConsumerStatefulWidget {
  const _InvestmentPortfolioForm({required this.existing, required this.dirty});

  final InvestmentPortfolio? existing;
  final FormDirtyController dirty;

  @override
  ConsumerState<_InvestmentPortfolioForm> createState() =>
      _InvestmentPortfolioFormState();
}

class _InvestmentPortfolioFormState
    extends ConsumerState<_InvestmentPortfolioForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  PortfolioStrategyKind _strategy = PortfolioStrategyKind.indexCore;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    widget.dirty.bindTextControllers([_name]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final languageCode = Localizations.localeOf(context).languageCode;
    final baseCurrency = ref.read(baseCurrencyProvider);
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      final existing = widget.existing;
      if (existing == null) {
        final templates =
            ref.read(portfolioStrategyTemplatesProvider).value ??
            kBuiltInPortfolioStrategyTemplates;
        final initialStrategy = templates.firstWhere(
          (template) => template.kind == _strategy,
          orElse: () => kIndexCoreStrategyTemplate,
        );
        await repository.create(
          name: _name.text,
          initialStrategy: initialStrategy,
          baseCurrency: baseCurrency,
          languageCode: languageCode,
        );
      } else {
        await repository.update(existing.copyWith(name: _name.text));
      }
      widget.dirty.markPristine();
      widget.dirty.busy = false;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.dirty.busy = false;
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).portfolioSaveFailed,
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final l10n = AppLocalizations.of(context);
    final portfolios =
        ref.read(investmentPortfoliosProvider).value ??
        const <InvestmentPortfolio>[];
    final groups =
        ref.read(portfolioRebalanceGroupsProvider).value ??
        const <PortfolioRebalanceGroup>[];
    final assignments =
        ref.read(portfolioCapitalAssignmentsProvider).value ??
        const <PortfolioCapitalAssignment>[];
    final targets =
        ref.read(activeUniversePortfolioTargetsProvider).value ??
        const <PortfolioAllocationTarget>[];
    final portfolioById = {
      for (final portfolio in portfolios) portfolio.id: portfolio,
    };
    final destinations = groups
        .where((group) => group.portfolioId != existing.id)
        .toList(growable: false);
    String? destinationGroupId;
    if (destinations.isEmpty) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: Text(l10n.portfolioDeleteAction),
        body: Text(l10n.portfolioDeleteConfirmation),
        confirmLabel: l10n.commonDelete,
        cancelLabel: l10n.commonCancel,
        destructive: true,
        icon: FLucideIcons.trash2,
      );
      if (confirmed != true || !mounted) return;
    } else {
      destinationGroupId = await showRemovalTransferSheet(
        context: context,
        title: l10n.portfolioDeleteAction,
        description: l10n.portfolioDeleteTransferDescription(
          _percentFromBps(
            targets
                    .where((target) => target.portfolioId == existing.id)
                    .firstOrNull
                    ?.targetWeightBps ??
                0,
          ),
          assignments
              .where((assignment) => assignment.portfolioId == existing.id)
              .length,
        ),
        options: [
          for (final destination in destinations)
            RemovalTransferOption(
              id: destination.id,
              title:
                  '${portfolioById[destination.portfolioId]?.name ?? destination.portfolioId} · ${destination.name}',
              subtitle: l10n.portfolioGroupWeightSummary(
                _percentFromBps(destination.targetWeightBps),
                _transferPolicyLabel(l10n, destination.transferPolicy),
              ),
            ),
        ],
      );
      if (destinationGroupId == null || !mounted) return;
    }
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      final destinationGroup = destinationGroupId == null
          ? null
          : destinations.firstWhere((group) => group.id == destinationGroupId);
      await repository.remove(
        existing,
        destinationPortfolioId: destinationGroup?.portfolioId,
        destinationGroupId: destinationGroup?.id,
      );
      if (ref.read(selectedInvestmentPortfolioIdProvider) == existing.id) {
        ref.read(selectedInvestmentPortfolioIdProvider.notifier).state = null;
      }
      widget.dirty.markPristine();
      widget.dirty.busy = false;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.dirty.busy = false;
      AppMessenger.show(
        context,
        ToastKind.error,
        portfolioRemovalErrorMessage(
          l10n,
          error,
          fallback: l10n.portfolioDeleteFailed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templates =
        ref.watch(portfolioStrategyTemplatesProvider).value ??
        kBuiltInPortfolioStrategyTemplates;
    final ownerTemplates = templates
        .where(
          (template) =>
              template.defaultCapitalRole == StrategyCapitalRole.owner,
        )
        .toList(growable: false);
    final locale = Localizations.localeOf(context);
    final removalDataReady =
        ref.watch(investmentPortfoliosProvider).hasValue &&
        ref.watch(portfolioRebalanceGroupsProvider).hasValue &&
        ref.watch(portfolioCapitalAssignmentsProvider).hasValue &&
        ref.watch(activeUniversePortfolioTargetsProvider).hasValue;
    return AppSheet(
      title: widget.existing == null
          ? l10n.portfolioCreateTitle
          : l10n.portfolioEditTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextFormField(
              control: FTextFieldControl.managed(controller: _name),
              label: Text(l10n.portfolioNameLabel),
              validator: (value) => value?.trim().isEmpty ?? true
                  ? l10n.portfolioNameRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.s16),
            if (widget.existing == null) ...[
              Text(
                l10n.portfolioCreateApproachTitle,
                style: context.bodyCaptionStrongStyle,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.portfolioCreateApproachHint,
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s8),
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < ownerTemplates.length;
                      index++
                    ) ...[
                      Semantics(
                        selected: ownerTemplates[index].kind == _strategy,
                        child: FTile(
                          prefix: Icon(
                            strategyTemplateIcon(ownerTemplates[index]),
                          ),
                          title: Text(
                            ownerTemplates[index].displayName(
                              locale.languageCode,
                            ),
                          ),
                          subtitle: Text(
                            ownerTemplates[index].kind ==
                                    PortfolioStrategyKind.indexCore
                                ? l10n.portfolioCreateRecommendedHint
                                : l10n.portfolioCreateCustomizableHint,
                          ),
                          suffix: Icon(
                            ownerTemplates[index].kind == _strategy
                                ? FLucideIcons.circleCheck
                                : FLucideIcons.circle,
                            size: AppIconSizes.sm,
                            color: ownerTemplates[index].kind == _strategy
                                ? context.theme.colors.primary
                                : context.theme.colors.mutedForeground,
                          ),
                          onPress: () {
                            setState(
                              () => _strategy = ownerTemplates[index].kind,
                            );
                            widget.dirty.markDirty();
                          },
                        ),
                      ),
                      if (index != ownerTemplates.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.s24),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _busy || !removalDataReady ? null : _delete,
                child: Text(l10n.portfolioDeleteAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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

class _PortfolioCashAssignmentLoader extends ConsumerWidget {
  const _PortfolioCashAssignmentLoader({
    this.preferredGroupId,
    this.suggestedAmount,
  });

  final String? preferredGroupId;
  final Decimal? suggestedAmount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final assignments = ref.watch(portfolioCapitalAssignmentsProvider);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    final accounts = ref.watch(accountsStreamProvider);
    final balances = ref.watch(accountBalancesByIdProvider);
    if (portfolios.hasError ||
        assignments.hasError ||
        groups.hasError ||
        accounts.hasError ||
        balances.hasError) {
      final failed = [
        portfolios,
        assignments,
        groups,
        accounts,
        balances,
      ].firstWhere((value) => value.hasError);
      return AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          failed.error!,
          stackTrace: failed.stackTrace,
          operation: 'load portfolio cash assignments',
        ),
      );
    }
    if (!portfolios.hasValue ||
        !assignments.hasValue ||
        !groups.hasValue ||
        !accounts.hasValue ||
        !balances.hasValue) {
      return const Center(child: FCircularProgress());
    }
    return _PortfolioCashAssignmentForm(
      portfolios: portfolios.requireValue,
      assignments: assignments.requireValue
          .where(
            (assignment) =>
                assignment.sourceKind == PortfolioCapitalSourceKind.cashAccount,
          )
          .toList(growable: false),
      groups: groups.requireValue
          .where((group) => !group.archived)
          .toList(growable: false),
      accounts: accounts.requireValue
          .where((account) => account.category == AccountSide.asset)
          .toList(growable: false),
      availableByAccount: {
        for (final account in accounts.requireValue)
          account.id:
              balances.requireValue[account.id]
                  ?.legFor(account.currency)
                  ?.units ??
              Decimal.zero,
      },
      preferredGroupId: preferredGroupId,
      suggestedAmount: suggestedAmount,
    );
  }
}

class _PortfolioCashAssignmentForm extends ConsumerStatefulWidget {
  const _PortfolioCashAssignmentForm({
    required this.portfolios,
    required this.assignments,
    required this.groups,
    required this.accounts,
    required this.availableByAccount,
    required this.preferredGroupId,
    required this.suggestedAmount,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioCapitalAssignment> assignments;
  final List<PortfolioRebalanceGroup> groups;
  final List<Account> accounts;
  final Map<String, Decimal> availableByAccount;
  final String? preferredGroupId;
  final Decimal? suggestedAmount;

  @override
  ConsumerState<_PortfolioCashAssignmentForm> createState() =>
      _PortfolioCashAssignmentFormState();
}

class _PortfolioCashAssignmentFormState
    extends ConsumerState<_PortfolioCashAssignmentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _accountId;
  String? _groupId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.suggestedAmount?.toString());
    _groupId = widget.preferredGroupId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
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
    if (widget.accounts.isEmpty) {
      return AppEmptyState(
        icon: FLucideIcons.walletCards,
        title: l10n.portfolioCashNoAccounts,
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            Navigator.of(context).maybePop();
            context.push(FinanceRoutes.wealthAccounts);
          },
          child: Text(l10n.accountsHubManageBankAccounts),
        ),
      );
    }

    final portfolioNames = {
      for (final portfolio in widget.portfolios) portfolio.id: portfolio.name,
    };
    final groupLabels = {
      for (final group in widget.groups)
        group.id:
            '${portfolioNames[group.portfolioId] ?? group.portfolioId} · ${group.name}',
    };
    final accountById = {
      for (final account in widget.accounts) account.id: account,
    };
    final selectedAccount =
        accountById[_accountId] ?? widget.accounts.firstOrNull;
    final selectedGroupId = groupLabels.containsKey(_groupId)
        ? _groupId
        : widget.groups.firstOrNull?.id;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.assignments.isNotEmpty) ...[
            Text(
              l10n.portfolioCashAssignmentsTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < widget.assignments.length;
                    index++
                  ) ...[
                    Builder(
                      builder: (context) {
                        final assignment = widget.assignments[index];
                        final account = accountById[assignment.sourceId];
                        return FTile(
                          prefix: const Icon(FLucideIcons.banknote),
                          title: Text(account?.name ?? assignment.sourceId),
                          subtitle: Text(
                            l10n.portfolioCashAssignmentSummary(
                              assignment.amount.toString(),
                              assignment.currency ?? '',
                              groupLabels[assignment.rebalanceGroupId] ??
                                  assignment.rebalanceGroupId,
                            ),
                          ),
                          suffix: FButton.icon(
                            variant: FButtonVariant.ghost,
                            onPress: _busy ? null : () => _remove(assignment),
                            child: const Icon(FLucideIcons.x),
                          ),
                          onPress: _busy
                              ? null
                              : () =>
                                    _move(assignment, groupLabels: groupLabels),
                        );
                      },
                    ),
                    if (index != widget.assignments.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
          ],
          FSelect<String>.rich(
            enabled: !_busy,
            format: (id) => accountById[id]?.name ?? id,
            control: FSelectControl<String>.lifted(
              value: selectedAccount?.id,
              onChange: (value) => setState(() => _accountId = value),
            ),
            label: Text(l10n.portfolioCashAccountLabel),
            children: [
              for (final account in widget.accounts)
                FSelectItem<String>(
                  value: account.id,
                  title: Text(account.name),
                  subtitle: Text(account.currency),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          FSelect<String>.rich(
            enabled: !_busy,
            format: (id) => groupLabels[id] ?? id,
            control: FSelectControl<String>.lifted(
              value: selectedGroupId,
              onChange: (value) => setState(() => _groupId = value),
            ),
            label: Text(l10n.portfolioGroupNameLabel),
            children: [
              for (final group in widget.groups)
                FSelectItem<String>(
                  value: group.id,
                  title: Text(groupLabels[group.id]!),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _amount),
            label: Text(
              selectedAccount == null
                  ? l10n.portfolioCashAmountLabel
                  : '${l10n.portfolioCashAmountLabel} (${selectedAccount.currency})',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              final amount = Decimal.tryParse(value?.trim() ?? '');
              return amount == null || amount <= Decimal.zero
                  ? l10n.portfolioCashAmountInvalid
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          AppBusyButton(
            onPress: selectedAccount == null || selectedGroupId == null
                ? null
                : () => _assign(
                    account: selectedAccount,
                    groupId: selectedGroupId,
                  ),
            busy: _busy,
            label: l10n.portfolioAssignCashAction,
          ),
        ],
      ),
    );
  }

  Future<void> _assign({
    required Account account,
    required String groupId,
  }) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final group = widget.groups.firstWhere((item) => item.id == groupId);
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.assignCash(
        accountId: account.id,
        amount: Decimal.parse(_amount.text.trim()),
        availableAmount: widget.availableByAccount[account.id] ?? Decimal.zero,
        currency: account.currency,
        portfolioId: group.portfolioId,
        rebalanceGroupId: group.id,
      );
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

  Future<void> _remove(PortfolioCapitalAssignment assignment) async {
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

  Future<void> _move(
    PortfolioCapitalAssignment assignment, {
    required Map<String, String> groupLabels,
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
              format: (id) => groupLabels[id] ?? id,
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
                    title: Text(groupLabels[group.id]!),
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
        sourceCapacity:
            widget.availableByAccount[assignment.sourceId] ??
            assignment.amount ??
            Decimal.zero,
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
}

String _percentFromBps(int value) {
  final percent = value / 100;
  return percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(2);
}

String _transferPolicyLabel(AppLocalizations l10n, GroupTransferPolicy policy) {
  return switch (policy) {
    GroupTransferPolicy.bidirectional =>
      l10n.portfolioGroupTransferBidirectional,
    GroupTransferPolicy.inflowsOnly => l10n.portfolioGroupTransferInflowsOnly,
    GroupTransferPolicy.isolated => l10n.portfolioGroupTransferIsolated,
  };
}
