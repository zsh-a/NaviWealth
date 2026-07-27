import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';
import '../domain/strategy/portfolio_strategy.dart';

class PortfolioGroupsSection extends ConsumerWidget {
  const PortfolioGroupsSection({super.key, required this.portfolioId});

  final String portfolioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    return groups.whenOrLoading(
      context: context,
      onRetry: () => ref.invalidate(portfolioRebalanceGroupsProvider),
      data: (allGroups) {
        final items = allGroups
            .where((group) => group.portfolioId == portfolioId)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.portfolioGroupsSectionTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            if (items.isNotEmpty)
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      FTile(
                        prefix: const Icon(FLucideIcons.layers3),
                        title: Text(items[index].name),
                        subtitle: Text(
                          l10n.portfolioGroupWeightSummary(
                            _percentFromBps(items[index].targetWeightBps),
                            _transferPolicyLabel(
                              l10n,
                              items[index].transferPolicy,
                            ),
                          ),
                        ),
                        suffix: const Icon(
                          FLucideIcons.chevronRight,
                          size: AppIconSizes.sm,
                        ),
                        onPress: () =>
                            _showEditGroupSheet(context, group: items[index]),
                      ),
                      if (index != items.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.plus),
              onPress: () =>
                  _showAddGroupSheet(context, portfolioId: portfolioId),
              child: Text(l10n.portfolioGroupAddAction),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showAddGroupSheet(
  BuildContext context, {
  required String portfolioId,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioGroupAddAction,
    builder: (_) => _AddPortfolioGroupForm(portfolioId: portfolioId),
  );
}

class _AddPortfolioGroupForm extends ConsumerStatefulWidget {
  const _AddPortfolioGroupForm({required this.portfolioId});

  final String portfolioId;

  @override
  ConsumerState<_AddPortfolioGroupForm> createState() =>
      _AddPortfolioGroupFormState();
}

class _AddPortfolioGroupFormState
    extends ConsumerState<_AddPortfolioGroupForm> {
  PortfolioStrategyKind? _kind;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final strategies = ref.watch(portfolioStrategyConfigsProvider);
    return strategies.whenOrLoading(
      context: context,
      onRetry: () => ref.invalidate(portfolioStrategyConfigsProvider),
      data: (allStrategies) {
        final configured = allStrategies
            .where((strategy) => strategy.portfolioId == widget.portfolioId)
            .map((strategy) => strategy.kind)
            .toSet();
        final available = _builtInStrategyKinds
            .where((kind) => !configured.contains(kind))
            .toList(growable: false);
        if (available.isEmpty) {
          return AppEmptyState(
            icon: FLucideIcons.layers,
            title: l10n.portfolioGroupNoTemplates,
            action: FButton(
              variant: FButtonVariant.outline,
              onPress: () => Navigator.of(context).pop(),
              child: Text(l10n.commonDone),
            ),
          );
        }
        final selected = _kind ?? available.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FSelect<PortfolioStrategyKind>.rich(
              enabled: !_busy,
              format: (kind) => _strategyLabel(l10n, kind),
              control: FSelectControl<PortfolioStrategyKind>.lifted(
                value: selected,
                onChange: (value) {
                  if (!_busy) setState(() => _kind = value);
                },
              ),
              label: Text(l10n.portfolioStrategyLabel),
              children: [
                for (final kind in available)
                  FSelectItem<PortfolioStrategyKind>(
                    value: kind,
                    title: Text(_strategyLabel(l10n, kind)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            AppBusyButton(
              onPress: () => _add(selected),
              busy: _busy,
              label: l10n.portfolioGroupAddAction,
            ),
          ],
        );
      },
    );
  }

  Future<void> _add(PortfolioStrategyKind kind) async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.addCapitalStrategy(
        portfolioId: widget.portfolioId,
        kind: kind,
      );
      if (mounted) Navigator.of(context).pop();
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
}

Future<void> _showEditGroupSheet(
  BuildContext context, {
  required PortfolioRebalanceGroup group,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioGroupEditTitle,
    builder: (_) => _EditPortfolioGroupForm(group: group),
  );
}

class _EditPortfolioGroupForm extends ConsumerStatefulWidget {
  const _EditPortfolioGroupForm({required this.group});

  final PortfolioRebalanceGroup group;

  @override
  ConsumerState<_EditPortfolioGroupForm> createState() =>
      _EditPortfolioGroupFormState();
}

class _EditPortfolioGroupFormState
    extends ConsumerState<_EditPortfolioGroupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _band;
  late GroupTransferPolicy _policy;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group.name);
    _target = TextEditingController(
      text: _percentFromBps(widget.group.targetWeightBps),
    );
    _band = TextEditingController(
      text: _percentFromBps(widget.group.driftBandBps),
    );
    _policy = widget.group.transferPolicy;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _band.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.portfolioGroupNameLabel),
            validator: (value) => value?.trim().isEmpty ?? true
                ? l10n.portfolioNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _target),
            label: Text(l10n.portfolioGroupTargetWeightLabel),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_percentFormatter],
            validator: (value) => _validatePercent(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _band),
            label: Text(l10n.portfolioGroupDriftBandLabel),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_percentFormatter],
            validator: (value) => _validatePercent(value, l10n),
          ),
          const SizedBox(height: AppSpacing.s12),
          FSelect<GroupTransferPolicy>.rich(
            enabled: !_busy,
            format: (policy) => _transferPolicyLabel(l10n, policy),
            control: FSelectControl<GroupTransferPolicy>.lifted(
              value: _policy,
              onChange: (value) {
                if (!_busy && value != null) setState(() => _policy = value);
              },
            ),
            label: Text(l10n.portfolioGroupTransferPolicyLabel),
            children: [
              for (final policy in GroupTransferPolicy.values)
                FSelectItem<GroupTransferPolicy>(
                  value: policy,
                  title: Text(_transferPolicyLabel(l10n, policy)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      final targetBps = _bpsFromPercent(_target.text);
      await repository.updateGroup(
        widget.group.copyWith(
          name: _name.text.trim(),
          driftBandBps: _bpsFromPercent(_band.text),
          transferPolicy: _policy,
        ),
      );
      if (targetBps != widget.group.targetWeightBps) {
        await repository.setGroupTargetWeight(
          portfolioId: widget.group.portfolioId,
          groupId: widget.group.id,
          targetWeightBps: targetBps,
        );
      }
      if (mounted) Navigator.of(context).pop();
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
}

final _percentFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d{0,3}(\.\d{0,2})?'),
);

String? _validatePercent(String? value, AppLocalizations l10n) {
  final parsed = double.tryParse(value?.trim() ?? '');
  return parsed == null || parsed < 0 || parsed > 100
      ? l10n.targetAllocationEditorRangeError
      : null;
}

int _bpsFromPercent(String value) => (double.parse(value.trim()) * 100).round();

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

String _strategyLabel(AppLocalizations l10n, PortfolioStrategyKind strategy) {
  if (strategy == PortfolioStrategyKind.indexCore) {
    return l10n.portfolioStrategyIndexCore;
  }
  if (strategy == PortfolioStrategyKind.dividendIncome) {
    return l10n.portfolioStrategyDividendIncome;
  }
  if (strategy == PortfolioStrategyKind.optionsIncome) {
    return l10n.portfolioStrategyOptionsIncome;
  }
  return strategy.wire;
}

const _builtInStrategyKinds = [
  PortfolioStrategyKind.indexCore,
  PortfolioStrategyKind.dividendIncome,
  PortfolioStrategyKind.optionsIncome,
];
