import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';
import '../data/providers.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';

Future<void> showInvestmentPortfolioManager(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioManageTitle,
    builder: (_) => const _InvestmentPortfolioManager(),
  );
}

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

Future<void> showPortfolioLotAssignmentSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioAssignLotsTitle,
    subtitle: l10n.portfolioAssignLotsSubtitle,
    builder: (_) => const _PortfolioLotAssignmentLoader(),
  );
}

class _InvestmentPortfolioManager extends ConsumerWidget {
  const _InvestmentPortfolioManager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portfolios = ref.watch(investmentPortfoliosProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: () => showInvestmentPortfolioFormSheet(context),
          prefix: const Icon(FLucideIcons.plus),
          child: Text(l10n.portfolioCreateTitle),
        ),
        const SizedBox(height: AppSpacing.s16),
        portfolios.whenOrLoading(
          context: context,
          onRetry: () => ref.invalidate(investmentPortfoliosProvider),
          data: (items) {
            if (items.isEmpty) {
              return AppEmptyState(
                icon: FLucideIcons.layers,
                title: l10n.portfolioNoPortfolios,
                action: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showInvestmentPortfolioFormSheet(context),
                  child: Text(l10n.portfolioCreateTitle),
                ),
              );
            }
            return AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    FTile(
                      prefix: Icon(
                        _strategyIcon(items[index].strategy),
                        color: context.theme.colors.mutedForeground,
                      ),
                      title: Text(items[index].name),
                      subtitle: Text(
                        _strategyLabel(l10n, items[index].strategy),
                      ),
                      suffix: Icon(
                        FLucideIcons.chevronRight,
                        size: AppIconSizes.sm,
                        color: context.theme.colors.mutedForeground.withValues(
                          alpha: AppOpacity.disabled,
                        ),
                      ),
                      onPress: () => showInvestmentPortfolioFormSheet(
                        context,
                        existing: items[index],
                      ),
                    ),
                    if (index != items.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
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
  late final TextEditingController _annualIncome;
  late InvestmentPortfolioStrategy _strategy;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _annualIncome = TextEditingController(
      text: widget.existing?.targetAnnualIncome?.toString() ?? '',
    );
    _strategy = widget.existing?.strategy ?? InvestmentPortfolioStrategy.income;
    widget.dirty.bindTextControllers([_name, _annualIncome]);
  }

  @override
  void dispose() {
    _name.dispose();
    _annualIncome.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      final targetIncome = _annualIncome.text.trim().isEmpty
          ? null
          : Decimal.parse(_annualIncome.text.trim());
      final existing = widget.existing;
      if (existing == null) {
        await repository.create(
          name: _name.text,
          strategy: _strategy,
          targetAnnualIncome: targetIncome,
        );
      } else {
        await repository.update(
          InvestmentPortfolio(
            id: existing.id,
            name: _name.text,
            strategy: _strategy,
            baseCurrency: existing.baseCurrency,
            goalId: existing.goalId,
            targetAllocationJson: existing.targetAllocationJson,
            targetAnnualIncome: targetIncome,
            color: existing.color,
            createdAt: existing.createdAt,
            archived: existing.archived,
            sync: existing.sync,
          ),
        );
      }
      widget.dirty.markPristine();
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
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.remove(existing);
      if (ref.read(selectedInvestmentPortfolioIdProvider) == existing.id) {
        ref.read(selectedInvestmentPortfolioIdProvider.notifier).state = null;
      }
      widget.dirty.markPristine();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      widget.dirty.busy = false;
      AppMessenger.show(context, ToastKind.error, l10n.portfolioDeleteFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            FSelect<InvestmentPortfolioStrategy>.rich(
              format: (value) => _strategyLabel(l10n, value),
              control: FSelectControl<InvestmentPortfolioStrategy>.lifted(
                value: _strategy,
                onChange: (value) {
                  if (value == null) return;
                  setState(() => _strategy = value);
                  widget.dirty.markDirty();
                },
              ),
              label: Text(l10n.portfolioStrategyLabel),
              children: [
                for (final value in InvestmentPortfolioStrategy.values)
                  FSelectItem<InvestmentPortfolioStrategy>(
                    value: value,
                    title: Text(_strategyLabel(l10n, value)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _annualIncome),
              label: Text(l10n.portfolioAnnualIncomeTargetLabel),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: (value) {
                final raw = value?.trim() ?? '';
                if (raw.isEmpty) return null;
                final parsed = Decimal.tryParse(raw);
                return parsed == null || parsed.sign < 0
                    ? l10n.portfolioAnnualIncomeTargetLabel
                    : null;
              },
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.s24),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _busy ? null : _delete,
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
  const _PortfolioLotAssignmentLoader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final memberships = ref.watch(portfolioLotMembershipsProvider);
    final lots = ref.watch(allInvestmentLotsProvider);
    final assets = ref.watch(allAssetsStreamProvider);
    if (portfolios.hasError ||
        memberships.hasError ||
        lots.hasError ||
        assets.hasError) {
      final failed = [
        portfolios,
        memberships,
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
        !memberships.hasValue ||
        !lots.hasValue ||
        !assets.hasValue) {
      return const Center(child: FCircularProgress());
    }
    return _PortfolioLotAssignmentForm(
      key: ValueKey(
        Object.hash(
          portfolios.value,
          memberships.value,
          lots.value,
          assets.value,
        ),
      ),
      portfolios: portfolios.requireValue,
      memberships: memberships.requireValue,
      lots: lots.requireValue.where((lot) => !lot.isClosed).toList(),
      assetLabels: {
        for (final asset in assets.requireValue)
          asset.id: asset.name?.trim().isNotEmpty == true
              ? asset.name!.trim()
              : asset.symbol,
      },
    );
  }
}

class _PortfolioLotAssignmentForm extends ConsumerStatefulWidget {
  const _PortfolioLotAssignmentForm({
    super.key,
    required this.portfolios,
    required this.memberships,
    required this.lots,
    required this.assetLabels,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioLotMembership> memberships;
  final List<Lot> lots;
  final Map<String, String> assetLabels;

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
      for (final membership in widget.memberships)
        membership.lotId: membership.portfolioId,
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
        if (entry.value.isEmpty) {
          await repository.unassignLot(entry.key);
        } else {
          await repository.assignLot(
            lotId: entry.key,
            portfolioId: entry.value,
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
    final labels = {
      for (final portfolio in widget.portfolios) portfolio.id: portfolio.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lot in widget.lots) ...[
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
              for (final portfolio in widget.portfolios)
                FSelectItem<String>(
                  value: portfolio.id,
                  title: Text(portfolio.name),
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
}

String _strategyLabel(
  AppLocalizations l10n,
  InvestmentPortfolioStrategy strategy,
) {
  return switch (strategy) {
    InvestmentPortfolioStrategy.income => l10n.portfolioStrategyIncome,
    InvestmentPortfolioStrategy.growth => l10n.portfolioStrategyGrowth,
    InvestmentPortfolioStrategy.preservation =>
      l10n.portfolioStrategyPreservation,
    InvestmentPortfolioStrategy.goalLinked => l10n.portfolioStrategyGoalLinked,
    InvestmentPortfolioStrategy.custom => l10n.portfolioStrategyCustom,
  };
}

IconData _strategyIcon(InvestmentPortfolioStrategy strategy) {
  return switch (strategy) {
    InvestmentPortfolioStrategy.income => FLucideIcons.handCoins,
    InvestmentPortfolioStrategy.growth => FLucideIcons.trendingUp,
    InvestmentPortfolioStrategy.preservation => FLucideIcons.shield,
    InvestmentPortfolioStrategy.goalLinked => FLucideIcons.target,
    InvestmentPortfolioStrategy.custom => FLucideIcons.layers,
  };
}
