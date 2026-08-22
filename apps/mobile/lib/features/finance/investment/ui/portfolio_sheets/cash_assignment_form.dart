part of '../investment_portfolio_sheets.dart';

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
