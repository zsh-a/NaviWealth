import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../rebalance/domain/portfolio_rebalance_group.dart';
import '../data/investment_portfolio_providers.dart';
import '../data/providers.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
import 'portfolio_allocation_sheets.dart';
import 'portfolio_group_sheets.dart';
import 'portfolio_strategy_visuals.dart';

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

Future<void> showPortfolioCashAssignmentSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioAssignCashTitle,
    subtitle: l10n.portfolioAssignCashSubtitle,
    builder: (_) => const _PortfolioCashAssignmentLoader(),
  );
}

Future<void> showPortfolioCapitalAssignmentCenter(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioCapitalAssignmentTitle,
    subtitle: l10n.portfolioCapitalAssignmentSubtitle,
    builder: (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: () => showPortfolioLotAssignmentSheet(context),
          prefix: const Icon(FLucideIcons.briefcaseBusiness),
          child: Text(l10n.portfolioCapitalAssignmentLotsAction),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          l10n.portfolioCapitalAssignmentLotsHint,
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s16),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showPortfolioCashAssignmentSheet(context),
          prefix: const Icon(FLucideIcons.walletCards),
          child: Text(l10n.portfolioCapitalAssignmentCashAction),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          l10n.portfolioCapitalAssignmentCashHint,
          style: context.captionStyle,
        ),
      ],
    ),
  );
}

class _InvestmentPortfolioManager extends ConsumerWidget {
  const _InvestmentPortfolioManager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final strategies = ref.watch(portfolioStrategyConfigsProvider);
    final templates = ref.watch(portfolioStrategyTemplatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: () => showInvestmentPortfolioFormSheet(context),
          prefix: const Icon(FLucideIcons.plus),
          child: Text(l10n.portfolioCreateTitle),
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showPortfolioStrategyLibrarySheet(context),
          prefix: const Icon(FLucideIcons.settings2),
          child: Text(l10n.portfolioStrategyLibraryTitle),
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showPortfolioCapitalAssignmentCenter(context),
          prefix: const Icon(FLucideIcons.walletCards),
          child: Text(l10n.portfolioCapitalAssignmentTitle),
        ),
        const SizedBox(height: AppSpacing.s16),
        const PortfolioAllocationPlanSection(),
        const SizedBox(height: AppSpacing.s16),
        switch ((portfolios, strategies, templates)) {
          (
            AsyncData(value: final items),
            AsyncData(value: final configs),
            AsyncData(value: final catalog),
          ) =>
            _PortfolioList(
              portfolios: items,
              strategies: configs,
              templates: catalog,
            ),
          (AsyncError(:final error, :final stackTrace), _, _) ||
          (_, AsyncError(:final error, :final stackTrace), _) ||
          (
            _,
            _,
            AsyncError(:final error, :final stackTrace),
          ) => AppEmptyState.error(
            title: userSafeErrorMessage(
              context,
              error,
              stackTrace: stackTrace,
              operation: 'load investment portfolios',
            ),
            action: FButton(
              variant: FButtonVariant.outline,
              onPress: () {
                ref.invalidate(investmentPortfoliosProvider);
                ref.invalidate(portfolioStrategyConfigsProvider);
                ref.invalidate(customPortfolioStrategyTemplatesProvider);
              },
              child: Text(l10n.commonRetry),
            ),
          ),
          _ => const Center(child: FCircularProgress()),
        },
      ],
    );
  }
}

class _PortfolioList extends StatelessWidget {
  const _PortfolioList({
    required this.portfolios,
    required this.strategies,
    required this.templates,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioStrategyConfig> strategies;
  final List<PortfolioStrategyTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (portfolios.isEmpty) {
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
          for (var index = 0; index < portfolios.length; index++) ...[
            Builder(
              builder: (context) {
                final portfolio = portfolios[index];
                final primaryStrategy = strategies
                    .where(
                      (strategy) =>
                          strategy.portfolioId == portfolio.id &&
                          strategy.enabled,
                    )
                    .firstOrNull;
                final template = primaryStrategy == null
                    ? null
                    : strategyTemplateForKind(templates, primaryStrategy.kind);
                return FTile(
                  prefix: Icon(
                    strategyTemplateIcon(template),
                    color: context.theme.colors.mutedForeground,
                  ),
                  title: Text(portfolio.name),
                  subtitle: Text(
                    primaryStrategy == null
                        ? l10n.portfolioStrategyCustom
                        : template?.displayName(
                                Localizations.localeOf(context).languageCode,
                              ) ??
                              primaryStrategy.kind.wire,
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
                    existing: portfolio,
                  ),
                );
              },
            ),
            if (index != portfolios.length - 1)
              const AppGroupedDivider(
                indent: AppSpacing.s12,
                endIndent: AppSpacing.s12,
              ),
          ],
        ],
      ),
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
              FSelect<PortfolioStrategyKind>.rich(
                format: (value) =>
                    strategyTemplateForKind(
                      ownerTemplates,
                      value,
                    )?.displayName(locale.languageCode) ??
                    value.wire,
                control: FSelectControl<PortfolioStrategyKind>.lifted(
                  value: _strategy,
                  onChange: (value) {
                    if (value == null) return;
                    setState(() => _strategy = value);
                    widget.dirty.markDirty();
                  },
                ),
                label: Text(l10n.portfolioStrategyLabel),
                children: [
                  for (final template in ownerTemplates)
                    FSelectItem<PortfolioStrategyKind>(
                      value: template.kind,
                      title: Text(template.displayName(locale.languageCode)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.s24),
              PortfolioGroupsSection(portfolioId: widget.existing!.id),
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
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioCapitalAssignment> assignments;
  final List<PortfolioRebalanceGroup> groups;
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
          await repository.unassignCapital(prior);
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
    final labels = {
      for (final group in widget.groups)
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
            enabled: !_busy && !partialLotIds.contains(lot.id),
            label: Text(widget.assetLabels[lot.assetId] ?? lot.assetId),
            description: Text(
              '${lot.remainingQuantity} · ${lot.openedAt.toLocal().toIso8601String().substring(0, 10)}',
            ),
            children: [
              FSelectItem<String>(
                value: '',
                title: Text(l10n.portfolioUnassigned),
              ),
              for (final group in widget.groups)
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
}

class _PortfolioCashAssignmentLoader extends ConsumerWidget {
  const _PortfolioCashAssignmentLoader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final assignments = ref.watch(portfolioCapitalAssignmentsProvider);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    final accounts = ref.watch(accountsStreamProvider);
    if (portfolios.hasError ||
        assignments.hasError ||
        groups.hasError ||
        accounts.hasError) {
      final failed = [
        portfolios,
        assignments,
        groups,
        accounts,
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
        !accounts.hasValue) {
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
    );
  }
}

class _PortfolioCashAssignmentForm extends ConsumerStatefulWidget {
  const _PortfolioCashAssignmentForm({
    required this.portfolios,
    required this.assignments,
    required this.groups,
    required this.accounts,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioCapitalAssignment> assignments;
  final List<PortfolioRebalanceGroup> groups;
  final List<Account> accounts;

  @override
  ConsumerState<_PortfolioCashAssignmentForm> createState() =>
      _PortfolioCashAssignmentFormState();
}

class _PortfolioCashAssignmentFormState
    extends ConsumerState<_PortfolioCashAssignmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _accountId;
  String? _groupId;
  bool _busy = false;

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
}
