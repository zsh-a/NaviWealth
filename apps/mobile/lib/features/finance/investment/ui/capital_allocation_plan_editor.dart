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
    maxHeightFactor: 0.98,
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
  late final Map<String, TextEditingController> _bandControllers;
  final _errors = <String, String>{};
  String? _expandedAdvancedId;
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
    if (_drafts.length > 1 && _totalBps != 10000) {
      final delta = 10000 - _totalBps;
      final last = _drafts.last;
      final adjustedLast = last.targetWeightBps + delta;
      if (adjustedLast >= 0 && adjustedLast <= 10000) {
        _drafts = [
          ..._drafts.take(_drafts.length - 1),
          last.copyWith(targetWeightBps: adjustedLast),
        ];
      } else {
        final sourceTotal = _totalBps;
        var assigned = 0;
        final normalized = <CapitalAllocationDraft>[];
        for (var index = 0; index < _drafts.length; index++) {
          final weight = index == _drafts.length - 1
              ? 10000 - assigned
              : (_drafts[index].targetWeightBps * 10000) ~/ sourceTotal;
          assigned += weight;
          normalized.add(_drafts[index].copyWith(targetWeightBps: weight));
        }
        _drafts = normalized;
      }
    }
    _bandControllers = {
      for (final draft in _drafts)
        draft.id: TextEditingController(
          text: _percentFromBps(draft.driftBandBps),
        ),
    };
    for (var index = 0; index < _drafts.length; index++) {
      final draftId = _drafts[index].id;
      _bandControllers[draftId]!.addListener(
        () => _updateBand(index, _bandControllers[draftId]!.text),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _bandControllers.values) {
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
    final isMobile = Breakpoints.isMobile(MediaQuery.sizeOf(context).width);
    final totalColor = context.theme.colors.primary;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * (isMobile ? 0.84 : 0.72),
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
          const SizedBox(height: AppSpacing.s12),
          if (isMobile)
            AppBusyButton(onPress: _save, busy: _busy, label: l10n.commonSave)
          else
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
    final advancedExpanded = _expandedAdvancedId == draft.id;
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.sm,
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        advancedExpanded
                            ? _policyLabel(l10n, draft.transferPolicy)
                            : widget.weightLabel,
                        style: context.microCaptionStyle,
                      ),
                    ],
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: _busy
                      ? null
                      : () => setState(() {
                          _expandedAdvancedId = advancedExpanded
                              ? null
                              : draft.id;
                        }),
                  child: Icon(
                    advancedExpanded
                        ? FLucideIcons.chevronUp
                        : FLucideIcons.settings2,
                    size: AppIconSizes.sm,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: '${draft.name}, ${widget.weightLabel}',
                    value: '${_percentFromBps(draft.targetWeightBps)} percent',
                    child: Material(
                      type: MaterialType.transparency,
                      child: Slider(
                        value: draft.targetWeightBps.toDouble(),
                        min: 0,
                        max: 10000,
                        divisions: 200,
                        semanticFormatterCallback: (value) =>
                            '${_percentFromBps(value.round())}%',
                        onChanged: _busy || _drafts.length == 1
                            ? null
                            : (value) => _setWeightLocked(
                                index,
                                (value / 50).round() * 50,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                SizedBox(
                  width: AppSpacing.s56,
                  child: Text(
                    '${_percentFromBps(draft.targetWeightBps)}%',
                    textAlign: TextAlign.end,
                    style: TypographyTokens.numericBodyStrong,
                  ),
                ),
              ],
            ),
            if (advancedExpanded) ...[
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

  void _updateBand(int index, String value) {
    if (_writingControllers) return;
    final draft = _drafts[index];
    final parsed = double.tryParse(value.trim());
    setState(() {
      if (parsed == null || parsed < 0 || parsed > 100) {
        _errors['band:${draft.id}'] = AppLocalizations.of(context)
            .targetAllocationEditorRangeError;
      } else {
        _errors.remove('band:${draft.id}');
        _drafts[index] = draft.copyWith(driftBandBps: (parsed * 100).round());
      }
    });
  }

  Future<void> _save() async {
    if (!_isValid) {
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

  void _setWeightLocked(int selectedIndex, int selectedWeight) {
    final clamped = selectedWeight.clamp(0, 10000);
    final remaining = 10000 - clamped;
    final otherIndexes = [
      for (var index = 0; index < _drafts.length; index++)
        if (index != selectedIndex) index,
    ];
    final currentOtherTotal = otherIndexes.fold<int>(
      0,
      (sum, index) => sum + _drafts[index].targetWeightBps,
    );
    final weights = List<int>.filled(_drafts.length, 0);
    weights[selectedIndex] = clamped;
    if (otherIndexes.isEmpty) {
      weights[selectedIndex] = 10000;
      _setWeights(weights);
      return;
    }
    if (currentOtherTotal == 0) {
      final base = remaining ~/ otherIndexes.length;
      var remainder = remaining - base * otherIndexes.length;
      for (final index in otherIndexes) {
        weights[index] = base + (remainder-- > 0 ? 1 : 0);
      }
    } else {
      var assigned = 0;
      for (var position = 0; position < otherIndexes.length; position++) {
        final index = otherIndexes[position];
        final next = position == otherIndexes.length - 1
            ? remaining - assigned
            : (_drafts[index].targetWeightBps * remaining) ~/ currentOtherTotal;
        weights[index] = next;
        assigned += next;
      }
    }
    _setWeights(weights);
  }

  void _setWeights(List<int> weights) {
    _writingControllers = true;
    try {
      setState(() {
        _drafts = [
          for (var index = 0; index < _drafts.length; index++)
            _drafts[index].copyWith(targetWeightBps: weights[index]),
        ];
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
