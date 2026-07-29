import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/percent_input_formatter.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class CapitalAllocationDraft {
  const CapitalAllocationDraft({
    required this.id,
    required this.name,
    required this.targetWeightBps,
    required this.driftBandBps,
    required this.transferPolicy,
  });

  final String id;
  final String name;
  final int targetWeightBps;
  final int driftBandBps;
  final GroupTransferPolicy transferPolicy;

  CapitalAllocationDraft copyWith({
    int? targetWeightBps,
    int? driftBandBps,
    GroupTransferPolicy? transferPolicy,
  }) {
    return CapitalAllocationDraft(
      id: id,
      name: name,
      targetWeightBps: targetWeightBps ?? this.targetWeightBps,
      driftBandBps: driftBandBps ?? this.driftBandBps,
      transferPolicy: transferPolicy ?? this.transferPolicy,
    );
  }
}

Future<void> showCapitalAllocationPlanEditor({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String weightLabel,
  required String singleItemHint,
  required List<CapitalAllocationDraft> drafts,
  required Future<void> Function(List<CapitalAllocationDraft> drafts) onSave,
}) {
  return showAppSheet<void>(
    context: context,
    title: title,
    subtitle: subtitle,
    maxHeightFactor: 0.94,
    builder: (_) => _CapitalAllocationPlanEditor(
      weightLabel: weightLabel,
      singleItemHint: singleItemHint,
      initialDrafts: drafts,
      onSave: onSave,
    ),
  );
}

class _CapitalAllocationPlanEditor extends StatefulWidget {
  const _CapitalAllocationPlanEditor({
    required this.weightLabel,
    required this.singleItemHint,
    required this.initialDrafts,
    required this.onSave,
  });

  final String weightLabel;
  final String singleItemHint;
  final List<CapitalAllocationDraft> initialDrafts;
  final Future<void> Function(List<CapitalAllocationDraft> drafts) onSave;

  @override
  State<_CapitalAllocationPlanEditor> createState() =>
      _CapitalAllocationPlanEditorState();
}

class _CapitalAllocationPlanEditorState
    extends State<_CapitalAllocationPlanEditor> {
  late List<CapitalAllocationDraft> _drafts;
  late final Map<String, TextEditingController> _weightControllers;
  late final Map<String, TextEditingController> _bandControllers;
  final _errors = <String, String>{};
  bool _showAdvanced = false;
  bool _showTotalError = false;
  bool _busy = false;
  bool _writingControllers = false;

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (final draft in widget.initialDrafts)
        if (widget.initialDrafts.length == 1)
          draft.copyWith(targetWeightBps: 10000)
        else
          draft,
    ];
    _weightControllers = {
      for (final draft in _drafts)
        draft.id: TextEditingController(
          text: _percentFromBps(draft.targetWeightBps),
        ),
    };
    _bandControllers = {
      for (final draft in _drafts)
        draft.id: TextEditingController(
          text: _percentFromBps(draft.driftBandBps),
        ),
    };
    for (var index = 0; index < _drafts.length; index++) {
      final draftId = _drafts[index].id;
      _weightControllers[draftId]!.addListener(
        () => _updateWeight(index, _weightControllers[draftId]!.text),
      );
      _bandControllers[draftId]!.addListener(
        () => _updateBand(index, _bandControllers[draftId]!.text),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      ..._weightControllers.values,
      ..._bandControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _totalBps =>
      _drafts.fold<int>(0, (sum, draft) => sum + draft.targetWeightBps);

  bool get _isValid =>
      _drafts.isNotEmpty &&
      _errors.isEmpty &&
      _totalBps == 10000 &&
      _drafts.every(
        (draft) =>
            draft.targetWeightBps >= 0 &&
            draft.targetWeightBps <= 10000 &&
            draft.driftBandBps >= 0 &&
            draft.driftBandBps <= 10000,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalColor = _totalBps == 10000
        ? context.theme.colors.primary
        : context.theme.colors.destructive;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard.flat(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.capitalAllocationTotalLabel,
                          style: context.theme.typography.body.sm,
                        ),
                      ),
                      Text(
                        '${_percentFromBps(_totalBps)}%',
                        style: context.theme.typography.body.sm.copyWith(
                          color: totalColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  _AllocationBar(drafts: _drafts, valid: _totalBps == 10000),
                  if (_drafts.length > 1) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.s4,
                      children: [
                        FButton(
                          variant: FButtonVariant.ghost,
                          onPress: _busy ? null : _balanceEvenly,
                          prefix: const Icon(
                            FLucideIcons.columns3,
                            size: AppIconSizes.sm,
                          ),
                          child: Text(
                            l10n.capitalAllocationBalanceEvenlyAction,
                          ),
                        ),
                        FButton(
                          variant: FButtonVariant.ghost,
                          onPress: _busy || _totalBps == 10000
                              ? null
                              : _fillRemainder,
                          prefix: const Icon(
                            FLucideIcons.sparkles,
                            size: AppIconSizes.sm,
                          ),
                          child: Text(
                            l10n.capitalAllocationFillRemainderAction,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: ListView.separated(
              itemCount: _drafts.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.s12),
              itemBuilder: (context, index) => _buildRow(context, l10n, index),
            ),
          ),
          if (_drafts.length == 1) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(widget.singleItemHint, style: context.captionStyle),
          ],
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: _busy
                ? null
                : () => setState(() => _showAdvanced = !_showAdvanced),
            prefix: Icon(
              _showAdvanced ? FLucideIcons.chevronUp : FLucideIcons.settings2,
            ),
            child: Text(l10n.capitalAllocationAdvancedAction),
          ),
          if (_showTotalError || _totalBps != 10000)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: Text(
                l10n.capitalAllocationTotalHint(_percentFromBps(_totalBps)),
                style: context.captionStyle.copyWith(color: totalColor),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: AppSpacing.s12),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: l10n.commonSave,
            busy: _busy,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, AppLocalizations l10n, int index) {
    final draft = _drafts[index];
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(draft.name, style: context.theme.typography.body.sm),
            const SizedBox(height: AppSpacing.s8),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _weightControllers[draft.id]!,
              ),
              enabled: !_busy && _drafts.length > 1,
              label: Text(widget.weightLabel),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [percentInputFormatter],
              forceErrorText: _errors['weight:${draft.id}'],
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(
                  controller: _bandControllers[draft.id]!,
                ),
                enabled: !_busy,
                label: Text(l10n.capitalAllocationToleranceLabel),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [percentInputFormatter],
                forceErrorText: _errors['band:${draft.id}'],
              ),
              const SizedBox(height: AppSpacing.s12),
              FSelect<GroupTransferPolicy>.rich(
                enabled: !_busy,
                format: (policy) => _policyLabel(l10n, policy),
                control: FSelectControl<GroupTransferPolicy>.lifted(
                  value: draft.transferPolicy,
                  onChange: (value) {
                    if (value == null) return;
                    setState(() {
                      _drafts[index] = draft.copyWith(transferPolicy: value);
                    });
                  },
                ),
                label: Text(l10n.capitalAllocationRuleLabel),
                children: [
                  for (final policy in GroupTransferPolicy.values)
                    FSelectItem<GroupTransferPolicy>(
                      value: policy,
                      title: Text(_policyLabel(l10n, policy)),
                      subtitle: Text(_policyDescription(l10n, policy)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _updateWeight(int index, String value) {
    if (_writingControllers) return;
    final draft = _drafts[index];
    final parsed = double.tryParse(value.trim());
    setState(() {
      if (parsed == null || parsed < 0 || parsed > 100) {
        _errors['weight:${draft.id}'] = AppLocalizations.of(
          context,
        ).targetAllocationEditorRangeError;
      } else {
        _errors.remove('weight:${draft.id}');
        _drafts[index] = draft.copyWith(
          targetWeightBps: (parsed * 100).round(),
        );
      }
      _showTotalError = false;
    });
  }

  void _updateBand(int index, String value) {
    if (_writingControllers) return;
    final draft = _drafts[index];
    final parsed = double.tryParse(value.trim());
    setState(() {
      if (parsed == null || parsed < 0 || parsed > 100) {
        _errors['band:${draft.id}'] = AppLocalizations.of(
          context,
        ).targetAllocationEditorRangeError;
      } else {
        _errors.remove('band:${draft.id}');
        _drafts[index] = draft.copyWith(driftBandBps: (parsed * 100).round());
      }
    });
  }

  Future<void> _save() async {
    if (!_isValid) {
      setState(() => _showTotalError = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSave(List.unmodifiable(_drafts));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).capitalAllocationSaveFailed,
      );
    }
  }

  void _balanceEvenly() {
    final base = 10000 ~/ _drafts.length;
    var remainder = 10000 - (base * _drafts.length);
    _setWeights([
      for (var index = 0; index < _drafts.length; index++)
        base + (remainder-- > 0 ? 1 : 0),
    ]);
  }

  void _fillRemainder() {
    final delta = 10000 - _totalBps;
    final candidateIndex = _drafts.lastIndexWhere((draft) {
      final next = draft.targetWeightBps + delta;
      return next >= 0 && next <= 10000;
    });
    if (candidateIndex < 0) return;
    _setWeights([
      for (var index = 0; index < _drafts.length; index++)
        index == candidateIndex
            ? _drafts[index].targetWeightBps + delta
            : _drafts[index].targetWeightBps,
    ]);
  }

  void _setWeights(List<int> weights) {
    _writingControllers = true;
    try {
      setState(() {
        _errors.removeWhere((key, _) => key.startsWith('weight:'));
        _showTotalError = false;
        _drafts = [
          for (var index = 0; index < _drafts.length; index++)
            _drafts[index].copyWith(targetWeightBps: weights[index]),
        ];
        for (var index = 0; index < _drafts.length; index++) {
          _weightControllers[_drafts[index].id]!.text = _percentFromBps(
            weights[index],
          );
        }
      });
    } finally {
      _writingControllers = false;
    }
  }
}

class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.drafts, required this.valid});

  final List<CapitalAllocationDraft> drafts;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final positive = drafts
        .where((draft) => draft.targetWeightBps > 0)
        .toList(growable: false);
    final total = positive.fold<int>(
      0,
      (sum, draft) => sum + draft.targetWeightBps,
    );
    final remaining = (10000 - total).clamp(0, 10000);
    final colors = context.theme.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: valid ? colors.primary : colors.destructive,
          ),
        ),
        child: SizedBox(
          height: AppSpacing.s8,
          child: Row(
            children: [
              for (var index = 0; index < positive.length; index++)
                Expanded(
                  flex: positive[index].targetWeightBps,
                  child: ColoredBox(
                    color: colors.primary.withValues(
                      alpha: 1 - (index % 5) * 0.13,
                    ),
                  ),
                ),
              if (remaining > 0)
                Expanded(
                  flex: remaining,
                  child: ColoredBox(color: colors.muted),
                ),
            ],
          ),
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

String _policyLabel(AppLocalizations l10n, GroupTransferPolicy policy) {
  return switch (policy) {
    GroupTransferPolicy.bidirectional =>
      l10n.capitalAllocationRuleBidirectional,
    GroupTransferPolicy.inflowsOnly => l10n.capitalAllocationRuleInflowsOnly,
    GroupTransferPolicy.isolated => l10n.capitalAllocationRuleIsolated,
  };
}

String _policyDescription(AppLocalizations l10n, GroupTransferPolicy policy) {
  return switch (policy) {
    GroupTransferPolicy.bidirectional =>
      l10n.capitalAllocationRuleBidirectionalDescription,
    GroupTransferPolicy.inflowsOnly =>
      l10n.capitalAllocationRuleInflowsOnlyDescription,
    GroupTransferPolicy.isolated =>
      l10n.capitalAllocationRuleIsolatedDescription,
  };
}
