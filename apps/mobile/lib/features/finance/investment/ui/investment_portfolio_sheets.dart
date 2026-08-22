import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
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

part 'portfolio_sheets/assignment_pages.dart';
part 'portfolio_sheets/cash_assignment_form.dart';
part 'portfolio_sheets/lot_assignment_form.dart';

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
            AppFormSection(
              gap: AppSpacing.s16,
              children: [
                FTextFormField(
                  control: FTextFieldControl.managed(controller: _name),
                  label: Text(l10n.portfolioNameLabel),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? l10n.portfolioNameRequired
                      : null,
                ),
                if (widget.existing == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                                selected:
                                    ownerTemplates[index].kind == _strategy,
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
                                    color:
                                        ownerTemplates[index].kind == _strategy
                                        ? context.theme.colors.primary
                                        : context.theme.colors.mutedForeground,
                                  ),
                                  onPress: () {
                                    setState(
                                      () => _strategy =
                                          ownerTemplates[index].kind,
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
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
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
