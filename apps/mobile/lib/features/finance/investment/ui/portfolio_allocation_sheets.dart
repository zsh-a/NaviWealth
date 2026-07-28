import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';

class PortfolioAllocationSection extends ConsumerWidget {
  const PortfolioAllocationSection({super.key, required this.portfolioId});

  final String portfolioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final targets = ref.watch(activeUniversePortfolioTargetsProvider);
    return targets.whenOrLoading(
      context: context,
      onRetry: () => ref.invalidate(portfolioAllocationTargetsProvider),
      data: (items) {
        final target = items
            .where((item) => item.portfolioId == portfolioId)
            .firstOrNull;
        if (target == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.portfolioAllocationSectionTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: FTile(
                prefix: const Icon(FLucideIcons.gitCompareArrows),
                title: Text(
                  l10n.portfolioAllocationWeightSummary(
                    _percentFromBps(target.targetWeightBps),
                  ),
                ),
                subtitle: Text(
                  _transferPolicyLabel(l10n, target.transferPolicy),
                ),
                suffix: const Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                ),
                onPress: () =>
                    _showEditPortfolioTargetSheet(context, target: target),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showEditPortfolioTargetSheet(
  BuildContext context, {
  required PortfolioAllocationTarget target,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.portfolioAllocationEditTitle,
    builder: (_) => _EditPortfolioTargetForm(target: target),
  );
}

class _EditPortfolioTargetForm extends ConsumerStatefulWidget {
  const _EditPortfolioTargetForm({required this.target});

  final PortfolioAllocationTarget target;

  @override
  ConsumerState<_EditPortfolioTargetForm> createState() =>
      _EditPortfolioTargetFormState();
}

class _EditPortfolioTargetFormState
    extends ConsumerState<_EditPortfolioTargetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _target;
  late final TextEditingController _band;
  late GroupTransferPolicy _policy;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(
      text: _percentFromBps(widget.target.targetWeightBps),
    );
    _band = TextEditingController(
      text: _percentFromBps(widget.target.driftBandBps),
    );
    _policy = widget.target.transferPolicy;
  }

  @override
  void dispose() {
    _target.dispose();
    _band.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final targets = ref.watch(activeUniversePortfolioTargetsProvider).value;
    final canChangeTarget = targets != null && targets.length > 1;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _target),
            enabled: !_busy && canChangeTarget,
            label: Text(l10n.portfolioAllocationTargetWeightLabel),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_percentFormatter],
            validator: (value) => _validatePercent(value, l10n),
          ),
          if (targets?.length == 1) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              l10n.portfolioAllocationSingleTargetHint,
              style: context.captionStyle,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _band),
            enabled: !_busy,
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
                if (value != null) setState(() => _policy = value);
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
      await repository.updatePortfolioTargetConfiguration(
        target: widget.target.copyWith(
          driftBandBps: _bpsFromPercent(_band.text),
          transferPolicy: _policy,
        ),
        targetWeightBps: _bpsFromPercent(_target.text),
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
