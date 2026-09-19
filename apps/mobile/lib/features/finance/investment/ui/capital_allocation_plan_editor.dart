import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/percent_field.dart';
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
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _CapitalAllocationPlanEditor(
        title: title,
        subtitle: subtitle,
        weightLabel: weightLabel,
        singleItemHint: singleItemHint,
        initialDrafts: drafts,
        onSave: onSave,
      ),
    ),
  );
}

class _CapitalAllocationPlanEditor extends ConsumerStatefulWidget {
  const _CapitalAllocationPlanEditor({
    required this.title,
    required this.subtitle,
    required this.weightLabel,
    required this.singleItemHint,
    required this.initialDrafts,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final String weightLabel;
  final String singleItemHint;
  final List<CapitalAllocationDraft> initialDrafts;
  final Future<void> Function(List<CapitalAllocationDraft> drafts) onSave;

  @override
  ConsumerState<_CapitalAllocationPlanEditor> createState() =>
      _CapitalAllocationPlanEditorState();
}

class _CapitalAllocationPlanEditorState
    extends ConsumerState<_CapitalAllocationPlanEditor>
    with FormDirtyGuard<_CapitalAllocationPlanEditor> {
  late List<CapitalAllocationDraft> _drafts;
  late final List<CapitalAllocationDraft> _initialDrafts;
  late final Map<String, TextEditingController> _weightControllers;
  late final Map<String, FocusNode> _weightFocus;
  late final Map<String, GlobalKey> _fieldKeys;
  final _errors = <String, String>{};
  final _pendingWeights = <String>{};
  final _lastText = <String, String>{};
  bool _busy = false;
  bool _saveFailed = false;
  bool _writingControllers = false;

  @override
  String get leaveFallback => FinanceRoutes.wealthPortfolio;

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
    // Reset returns to the normalized entry snapshot, not a later save attempt.
    _initialDrafts = List.unmodifiable(_drafts);
    _weightControllers = {
      for (final draft in _drafts)
        draft.id: TextEditingController(
          text: _percentFromBps(draft.targetWeightBps),
        ),
    };
    _weightFocus = {for (final draft in _drafts) draft.id: FocusNode()};
    _fieldKeys = {for (final draft in _drafts) draft.id: GlobalKey()};
    for (var index = 0; index < _drafts.length; index++) {
      final id = _drafts[index].id;
      _lastText[id] = _weightControllers[id]!.text;
      _weightControllers[id]!.addListener(
        () => _updateWeight(index, _weightControllers[id]!.text),
      );
      _weightFocus[id]!.addListener(() {
        if (!_weightFocus[id]!.hasFocus && mounted && !_busy) {
          _commitWeight(index);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    for (final focus in _weightFocus.values) {
      focus.dispose();
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

  bool get _hasChanges =>
      _pendingWeights.isNotEmpty ||
      _drafts.indexed.any((entry) {
        final (index, draft) = entry;
        final original = _initialDrafts[index];
        return draft.targetWeightBps != original.targetWeightBps ||
            draft.driftBandBps != original.driftBandBps ||
            draft.transferPolicy != original.transferPolicy;
      });

  void _syncDirty() {
    if (_hasChanges) {
      dirty.markDirty();
    } else {
      dirty.markPristine();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(widget.title),
        confirmLeave: handleBackIntent,
        child: AppFormScaffoldBody(
          softActionBar: true,
          actionStatus: _busy
              ? AppGlassStatus.busy
              : _saveFailed || _errors.isNotEmpty
              ? AppGlassStatus.error
              : AppGlassStatus.idle,
          onSubmit: _busy ? null : _save,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saveFailed) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.capitalAllocationSaveFailed,
                    style: context.captionStyle.copyWith(
                      color: context.theme.colors.destructive,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              AppBusyButton(
                onPress: _save,
                busy: _busy,
                label: l10n.commonSave,
              ),
            ],
          ),
          children: [
            Text(widget.subtitle, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s16),
            Row(
              children: [
                Expanded(child: Text(l10n.capitalAllocationTotalLabel)),
                Text(
                  '${_percentFromBps(_totalBps)}%',
                  style: TypographyTokens.numericBodyStrong,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            _AllocationBar(drafts: _drafts, valid: _totalBps == 10000),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _drafts.length == 1
                  ? widget.singleItemHint
                  : l10n.capitalAllocationAutoBalanceHint,
              style: context.captionStyle,
            ),
            if (_drafts.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.s8,
                  children: [
                    FButton(
                      key: const ValueKey('allocation-restore'),
                      variant: FButtonVariant.ghost,
                      mainAxisSize: MainAxisSize.min,
                      onPress: _busy || !_hasChanges ? null : _restore,
                      child: Flexible(
                        child: Text(
                          l10n.capitalAllocationRestoreAction,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    if (_drafts.length > 1)
                      FButton(
                        variant: FButtonVariant.ghost,
                        mainAxisSize: MainAxisSize.min,
                        onPress: _busy ? null : _balanceEvenly,
                        child: Flexible(
                          child: Text(
                            l10n.capitalAllocationBalanceEvenlyAction,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            for (var index = 0; index < _drafts.length; index++) ...[
              const SizedBox(height: AppSpacing.s16),
              if (index > 0) const AppGroupedDivider(),
              _buildRow(context, l10n, index),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, AppLocalizations l10n, int index) {
    final draft = _drafts[index];
    final original = _initialDrafts[index];
    final currentRule = l10n.capitalAllocationRuleSummary(
      _policyLabel(l10n, draft.transferPolicy),
      _percentFromBps(draft.driftBandBps),
    );
    final originalRule = l10n.capitalAllocationRuleSummary(
      _policyLabel(l10n, original.transferPolicy),
      _percentFromBps(original.driftBandBps),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(draft.name, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          PercentField(
            key: _fieldKeys[draft.id],
            control: FTextFieldControl.managed(
              controller: _weightControllers[draft.id]!,
            ),
            focusNode: _weightFocus[draft.id],
            semanticLabel: '${draft.name}, ${widget.weightLabel}',
            label: Text(widget.weightLabel),
            enabled: !_busy && _drafts.length > 1,
            forceErrorText: _errors[draft.id],
            description: Text(
              l10n.capitalAllocationWeightComparison(
                _percentFromBps(original.targetWeightBps),
                _percentFromBps(draft.targetWeightBps),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmit: (_) {
              if (_commitWeight(index)) _weightFocus[draft.id]!.unfocus();
            },
          ),
          if (_drafts.length > 1)
            Slider(
              value: draft.targetWeightBps.toDouble(),
              min: 0,
              max: 10000,
              divisions: 200,
              semanticFormatterCallback: (value) =>
                  '${_percentFromBps(value.round())}%',
              onChanged: _busy
                  ? null
                  : (value) {
                      if (_commitPendingWeights()) {
                        _setWeightLocked(index, (value / 50).round() * 50);
                      }
                    },
            ),
          FTile(
            title: Text(l10n.capitalAllocationAdvancedAction, maxLines: 3),
            subtitle: Text(
              originalRule == currentRule
                  ? currentRule
                  : l10n.capitalAllocationRuleComparison(
                      originalRule,
                      currentRule,
                    ),
            ),
            suffix: const Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
            ),
            onPress: _busy ? null : () => _editRules(index),
          ),
        ],
      ),
    );
  }

  Future<void> _editRules(int index) async {
    if (!_commitPendingWeights()) {
      await _focusFirstError();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final updated = await showGuardedFormSheet<CapitalAllocationDraft>(
      context: context,
      builder: (_, guard) =>
          _AllocationRuleForm(draft: _drafts[index], dirty: guard),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _drafts[index] = updated;
      _saveFailed = false;
    });
    _syncDirty();
  }

  void _updateWeight(int index, String value) {
    final id = _drafts[index].id;
    if (_writingControllers || _lastText[id] == value) return;
    _lastText[id] = value;
    setState(() {
      _pendingWeights.add(id);
      _errors.remove(id);
      _saveFailed = false;
    });
    _syncDirty();
  }

  int? _parseWeight(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
      return null;
    }
    return (parsed * 100).round();
  }

  bool _commitWeight(int index) {
    final id = _drafts[index].id;
    if (!_pendingWeights.contains(id)) return !_errors.containsKey(id);
    final weight = _parseWeight(_weightControllers[id]!.text);
    if (weight == null) {
      setState(
        () =>
            _errors[id] = AppLocalizations.of(context)
                .targetAllocationEditorRangeError,
      );
      return false;
    }
    _pendingWeights.remove(id);
    _errors.remove(id);
    _setWeightLocked(index, weight, editingId: id);
    return true;
  }

  bool _commitPendingWeights() {
    for (final id in _pendingWeights.toList()) {
      _commitWeight(_drafts.indexWhere((draft) => draft.id == id));
    }
    return _errors.isEmpty;
  }

  Future<void> _focusFirstError() async {
    final invalidId = _drafts
        .where((draft) => _errors.containsKey(draft.id))
        .firstOrNull
        ?.id;
    if (invalidId == null) return;
    _weightFocus[invalidId]!.requestFocus();
    final fieldContext = _fieldKeys[invalidId]!.currentContext;
    if (fieldContext != null) await Scrollable.ensureVisible(fieldContext);
  }

  void _restore() {
    _pendingWeights.clear();
    _errors.clear();
    _drafts = List.of(_initialDrafts);
    _setWeights([for (final draft in _drafts) draft.targetWeightBps]);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _save() async {
    if (_busy) return;
    _commitPendingWeights();
    if (!_isValid) {
      await _focusFirstError();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    dirty.busy = true;
    try {
      await widget.onSave(List.unmodifiable(_drafts));
      if (!mounted) return;
      dirty.markPristine();
      dirty.busy = false;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saveFailed = true;
      });
      dirty.busy = false;
    }
  }

  void _balanceEvenly() {
    _pendingWeights.clear();
    _errors.clear();
    final base = 10000 ~/ _drafts.length;
    var remainder = 10000 - (base * _drafts.length);
    _setWeights([
      for (var index = 0; index < _drafts.length; index++)
        base + (remainder-- > 0 ? 1 : 0),
    ]);
  }

  void _setWeightLocked(
    int selectedIndex,
    int selectedWeight, {
    String? editingId,
  }) {
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
      _setWeights(weights, editingId: editingId);
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
    _setWeights(weights, editingId: editingId);
  }

  void _setWeights(List<int> weights, {String? editingId}) {
    _writingControllers = true;
    try {
      setState(() {
        _saveFailed = false;
        _drafts = [
          for (var index = 0; index < _drafts.length; index++)
            _drafts[index].copyWith(targetWeightBps: weights[index]),
        ];
        for (final draft in _drafts) {
          // Do not overwrite another field's incomplete or invalid input.
          if (draft.id != editingId && _pendingWeights.contains(draft.id)) {
            continue;
          }
          _errors.remove(draft.id);
          _weightControllers[draft.id]!.text = _percentFromBps(
            draft.targetWeightBps,
          );
          _lastText[draft.id] = _weightControllers[draft.id]!.text;
        }
      });
    } finally {
      _writingControllers = false;
    }
    _syncDirty();
  }
}

class _AllocationRuleForm extends StatefulWidget {
  const _AllocationRuleForm({required this.draft, required this.dirty});

  final CapitalAllocationDraft draft;
  final FormDirtyController dirty;

  @override
  State<_AllocationRuleForm> createState() => _AllocationRuleFormState();
}

class _AllocationRuleFormState extends State<_AllocationRuleForm> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  late final TextEditingController _band;
  late GroupTransferPolicy _policy;

  @override
  void initState() {
    super.initState();
    _band = TextEditingController(
      text: _percentFromBps(widget.draft.driftBandBps),
    );
    _policy = widget.draft.transferPolicy;
    widget.dirty.bindTextControllers([_band]);
  }

  @override
  void dispose() {
    _band.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) {
      _focus.requestFocus();
      return;
    }
    widget.dirty.markPristine();
    Navigator.of(context).pop(
      widget.draft.copyWith(
        driftBandBps: (double.parse(_band.text) * 100).round(),
        transferPolicy: _policy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.capitalAllocationAdvancedAction,
      subtitle: widget.draft.name,
      footer: AppSheetFooter(
        cancelLabel: l10n.commonCancel,
        submitLabel: l10n.capitalAllocationApplyRules,
        onSubmit: _apply,
      ),
      child: Form(
        key: _formKey,
        child: AppFormSection(
          children: [
            Text(
              l10n.capitalAllocationRulesDraftHint,
              style: context.captionStyle,
            ),
            PercentField(
              control: FTextFieldControl.managed(controller: _band),
              focusNode: _focus,
              label: Text(l10n.capitalAllocationToleranceLabel),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                return parsed == null ||
                        !parsed.isFinite ||
                        parsed < 0 ||
                        parsed > 100
                    ? l10n.targetAllocationEditorRangeError
                    : null;
              },
            ),
            FSelect<GroupTransferPolicy>.rich(
              format: (policy) => _policyLabel(l10n, policy),
              control: FSelectControl<GroupTransferPolicy>.lifted(
                value: _policy,
                onChange: (value) {
                  if (value == null) return;
                  setState(() => _policy = value);
                  widget.dirty.markDirty();
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
        ),
      ),
    );
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
