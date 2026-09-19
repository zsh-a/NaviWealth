import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/percent_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'watchlist_simulation_support.dart';

const int _kPercentScale = 100;

/// Reveal errors after their inline messages have been laid out, including
/// fields above the viewport of a long form. Respect reduced-motion settings.
void _revealSimulationField(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.12,
        duration: AppMotionPolicy.duration(context, Motion.componentChange),
        curve: Motion.standardDecelerate,
      ),
    );
  });
}

bool _validateSimulationForm(GlobalKey<FormState> key) {
  final form = key.currentState;
  if (form == null) return false;
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;
  _revealSimulationField(invalid.first.context);
  return false;
}

/// Creates a paper scenario for [collection].
///
/// Asks for the three things that actually shape the outcome — name, virtual
/// capital, and which symbols the scenario covers — instead of equal-weighting
/// the entire watchlist and forcing a second pass to fix it.
Future<void> showWatchlistSimulationCreatePage({
  required BuildContext context,
  required WatchlistCollection collection,
  required List<WatchlistItem> items,
  required List<WatchlistQuoteSnapshot> snapshots,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _WatchlistSimulationCreatePage(
        collection: collection,
        items: items,
        snapshots: snapshots,
      ),
    ),
  );
}

/// Full-page allocation editor with one guarded return path and pinned save.
Future<void> showWatchlistSimulationAllocationPage({
  required BuildContext context,
  required WatchlistSimulation simulation,
  required List<WatchlistSimulationPosition> positions,
  required Decimal cashWeight,
  required List<WatchlistItem> items,
  required List<WatchlistQuoteSnapshot> snapshots,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _WatchlistSimulationAllocationPage(
        simulation: simulation,
        positions: positions,
        cashWeight: cashWeight,
        items: items,
        snapshots: snapshots,
      ),
    ),
  );
}

/// Confirms, deletes, then offers a one-tap undo.
///
/// The delete is a tombstone (see [WatchlistSimulationRepository.delete]), so
/// undo restores the scenario together with its observed history.
Future<void> deleteWatchlistSimulation({
  required BuildContext context,
  required WatchlistSimulation simulation,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.watchlistSimulationDeleteTitle(simulation.name)),
    body: Text(l10n.watchlistSimulationDeleteBody),
    confirmLabel: l10n.watchlistSimulationDeleteAction,
    cancelLabel: l10n.commonCancel,
    destructive: true,
    icon: FLucideIcons.trash2,
  );
  if (confirmed != true || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final toastContext = context;
  try {
    final repository = await container.read(
      watchlistSimulationRepositoryProvider.future,
    );
    await repository.delete(simulation);
    if (!toastContext.mounted) return;
    AppMessenger.show(
      toastContext,
      ToastKind.info,
      l10n.watchlistSimulationDeleteUndo(simulation.name),
      duration: const Duration(seconds: 6),
      actionLabel: l10n.watchlistSimulationUndoAction,
      onAction: () => unawaited(
        _restoreSimulation(container, toastContext, simulation, l10n),
      ),
    );
  } catch (_) {
    if (toastContext.mounted) {
      AppMessenger.show(
        toastContext,
        ToastKind.error,
        l10n.watchlistSimulationDeleteFailed,
      );
    }
  }
}

Future<void> _restoreSimulation(
  ProviderContainer container,
  BuildContext context,
  WatchlistSimulation simulation,
  AppLocalizations l10n,
) async {
  try {
    final repository = await container.read(
      watchlistSimulationRepositoryProvider.future,
    );
    await repository.restore(simulation);
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.watchlistSimulationRestoreFailed,
      );
    }
  }
}

class _WatchlistSimulationCreatePage extends ConsumerStatefulWidget {
  const _WatchlistSimulationCreatePage({
    required this.collection,
    required this.items,
    required this.snapshots,
  });

  final WatchlistCollection collection;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  ConsumerState<_WatchlistSimulationCreatePage> createState() =>
      _WatchlistSimulationCreatePageState();
}

class _WatchlistSimulationCreatePageState
    extends ConsumerState<_WatchlistSimulationCreatePage>
    with FormDirtyGuard<_WatchlistSimulationCreatePage> {
  @override
  String get leaveFallback => FinanceRoutes.wealthWatchlist;

  final _formKey = GlobalKey<FormState>();
  final _universeKey = GlobalKey();
  late final TextEditingController _name;
  late final TextEditingController _capital;
  late final TextEditingController _cash;
  late final Set<String> _selected;
  bool _saving = false;
  bool _showSelectionError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _capital = TextEditingController(text: '100000');
    _cash = TextEditingController(text: '0');
    _selected = {for (final item in widget.items) item.id};
    dirty.bindTextControllers([_name, _capital, _cash]);
    dirty.snapshotBaseline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty && !dirty.isDirty) {
      _name.text = AppLocalizations.of(context)
          .watchlistSimulationDefaultName(widget.collection.name);
      dirty.snapshotBaseline();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final allSelected = _selected.length == widget.items.length;
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(l10n.watchlistSimulationCreateTitle),
        confirmLeave: handleBackIntent,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ExcludeFocus(
            excluding: _saving,
            child: AbsorbPointer(
              absorbing: _saving,
              child: AppFormScaffoldBody(
                softActionBar: true,
                actionStatus: _saving
                    ? AppGlassStatus.busy
                    : AppGlassStatus.idle,
                onSubmit: _saving ? null : _save,
                action: AppBusyButton(
                  label: l10n.watchlistSimulationCreateAction,
                  busy: _saving,
                  onPress: _save,
                ),
                children: [
                  Text(
                    l10n.watchlistSimulationIsolationNote,
                    style: context.captionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  AppSheetSectionLabel(l10n.watchlistSimulationBasicsSection),
                  _WatchlistSimulationNameField(controller: _name),
                  const SizedBox(height: AppSpacing.s12),
                  AmountField(
                    label: l10n.watchlistSimulationCapitalField(baseCurrency),
                    controller: _capital,
                    currencyCode: baseCurrency,
                    allowZero: false,
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  Text(
                    l10n.watchlistSimulationUniverseSection,
                    key: _universeKey,
                    style: context.labelStyle,
                  ),
                  Wrap(
                    spacing: AppSpacing.s12,
                    runSpacing: AppSpacing.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.watchlistSimulationUniverseSummary(
                          _selected.length,
                          widget.items.length,
                        ),
                        style: context.captionStyle,
                      ),
                      AppActionButton(
                        variant: FButtonVariant.ghost,
                        mainAxisSize: MainAxisSize.min,
                        hapticIntent: AppInteractionIntent.select,
                        onPress: _toggleAll,
                        child: Flexible(
                          child: Text(
                            allSelected
                                ? l10n.watchlistSimulationUniverseNone
                                : l10n.watchlistSimulationUniverseAll,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showSelectionError && _selected.isEmpty)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.watchlistSimulationUniverseRequired,
                        style: context.captionStyle.copyWith(
                          color: context.theme.colors.destructive,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.s8),
                  _WatchlistSimulationSymbolList(
                    items: widget.items,
                    isSelected: _selected.contains,
                    onToggle: _toggleSymbol,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  PercentField(
                    control: FTextFieldControl.managed(controller: _cash),
                    label: Text(l10n.watchlistSimulationCashPercentField),
                    validator: (value) => _validatePercent(context, value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleAll() {
    dirty.markDirty();
    setState(() {
      if (_selected.length == widget.items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.items.map((item) => item.id));
      }
    });
  }

  void _toggleSymbol(String itemId) {
    dirty.markDirty();
    setState(() {
      if (!_selected.remove(itemId)) _selected.add(itemId);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _showSelectionError = _selected.isEmpty);
    if (!_validateSimulationForm(_formKey)) return;
    if (_selected.isEmpty) {
      _revealSimulationField(_universeKey.currentContext!);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    dirty.busy = true;
    try {
      final repository = await ref.read(
        watchlistSimulationRepositoryProvider.future,
      );
      final selectedIds = widget.items
          .where((item) => _selected.contains(item.id))
          .map((item) => item.id)
          .toList(growable: false);
      final cashPercent = Decimal.parse(_cash.text.trim());
      final weightTexts = watchlistSimulationSplitPercentTexts(
        ids: selectedIds,
        totalPercent: Decimal.fromInt(_kPercentScale) - cashPercent,
      );
      final targetWeights = <String, Decimal>{};
      for (final entry in weightTexts.entries) {
        final ratio = watchlistSimulationPercentToRatio(
          Decimal.parse(entry.value),
        );
        if (ratio > Decimal.zero) targetWeights[entry.key] = ratio;
      }
      await repository.create(
        collectionId: widget.collection.id,
        name: _name.text,
        baseCurrency: ref.read(baseCurrencyProvider),
        startingCapital: Decimal.parse(_capital.text.trim()),
        targetWeights: targetWeights,
        cashWeight: watchlistSimulationPercentToRatio(cashPercent),
        holdingInputs: watchlistSimulationHoldingInputs(
          widget.items,
          widget.snapshots,
        ),
      );
      dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          _simulationSaveErrorMessage(error, l10n: l10n),
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WatchlistSimulationAllocationPage extends ConsumerStatefulWidget {
  const _WatchlistSimulationAllocationPage({
    required this.simulation,
    required this.positions,
    required this.cashWeight,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationPosition> positions;
  final Decimal cashWeight;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  ConsumerState<_WatchlistSimulationAllocationPage> createState() =>
      _WatchlistSimulationAllocationPageState();
}

class _WatchlistSimulationAllocationPageState
    extends ConsumerState<_WatchlistSimulationAllocationPage>
    with FormDirtyGuard<_WatchlistSimulationAllocationPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealthWatchlist;

  final _formKey = GlobalKey<FormState>();
  final _allocationSummaryKey = GlobalKey();
  late final TextEditingController _name;
  late final TextEditingController _capital;
  late final TextEditingController _cash;
  late final Map<String, TextEditingController> _weights;
  late final List<String> _configured;
  bool _saving = false;
  bool _showAllocationError = false;

  @override
  void initState() {
    super.initState();
    final existing = {
      for (final position in widget.positions)
        position.watchlistItemId: position.targetWeight,
    };
    final cashText = watchlistSimulationPercentText(widget.cashWeight);
    _configured = [
      for (final entry in existing.entries)
        if (entry.value > Decimal.zero) entry.key,
    ];
    final percentTexts = watchlistSimulationSnapPercentTexts(
      ids: _configured,
      ratiosById: existing,
      cashPercentText: cashText,
    );
    // Controllers exist for every candidate symbol up front so the dirty guard
    // binds once; only `_configured` entries are rendered.
    _weights = {
      for (final id in {
        ...widget.items.map((item) => item.id),
        ...existing.keys,
      })
        id: TextEditingController(
          text:
              percentTexts[id] ??
              watchlistSimulationPercentText(existing[id] ?? Decimal.zero),
        ),
    };
    _name = TextEditingController(text: widget.simulation.name);
    _capital = TextEditingController(
      text: widget.simulation.startingCapital.toString(),
    );
    _cash = TextEditingController(text: cashText);
    dirty.bindTextControllers([_name, _capital, _cash, ..._weights.values]);
    dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    for (final controller in _weights.values) {
      controller.dispose();
    }
    _name.dispose();
    _capital.dispose();
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemById = {for (final item in widget.items) item.id: item};
    final baseCurrency = widget.simulation.baseCurrency;
    final allocated = _allocatedPercent();
    final remaining = Decimal.fromInt(_kPercentScale) - allocated;
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(l10n.watchlistSimulationAdjustTitle),
        confirmLeave: handleBackIntent,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ExcludeFocus(
            excluding: _saving,
            child: AbsorbPointer(
              absorbing: _saving,
              child: AppFormScaffoldBody(
                softActionBar: true,
                actionStatus: _saving
                    ? AppGlassStatus.busy
                    : AppGlassStatus.idle,
                onSubmit: _saving ? null : _save,
                action: AppBusyButton(
                  label: l10n.commonSave,
                  busy: _saving,
                  onPress: _save,
                ),
                children: [
                  AppSheetSectionLabel(l10n.watchlistSimulationBasicsSection),
                  _WatchlistSimulationNameField(controller: _name),
                  const SizedBox(height: AppSpacing.s12),
                  AmountField(
                    label: l10n.watchlistSimulationCapitalField(baseCurrency),
                    controller: _capital,
                    currencyCode: baseCurrency,
                    allowZero: false,
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  Text(
                    l10n.watchlistSimulationHoldingsSection,
                    style: context.labelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: [
                      if (_configured.isNotEmpty)
                        AppActionButton(
                          variant: FButtonVariant.ghost,
                          mainAxisSize: MainAxisSize.min,
                          hapticIntent: AppInteractionIntent.select,
                          onPress: _equalize,
                          child: Flexible(
                            child: Text(l10n.watchlistSimulationEqualizeAction),
                          ),
                        ),
                      AppActionButton(
                        variant: FButtonVariant.ghost,
                        mainAxisSize: MainAxisSize.min,
                        hapticIntent: AppInteractionIntent.select,
                        onPress: _fillCash,
                        child: Flexible(
                          child: Text(l10n.watchlistSimulationFillCashAction),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (_configured.isEmpty)
                    Text(
                      l10n.watchlistSimulationNoPositions,
                      style: context.captionStyle,
                    )
                  else
                    for (final id in _configured) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PercentField(
                              key: ValueKey<String>(
                                'watchlist-simulation-weight-$id',
                              ),
                              control: FTextFieldControl.managed(
                                controller: _weights[id]!,
                                onChange: (_) => setState(() {}),
                              ),
                              label: Text(
                                l10n.watchlistSimulationHoldingWeightField(
                                  watchlistSimulationSymbolLabel(
                                    itemById[id],
                                    fallbackId: id,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  _validatePercent(context, value),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.s6),
                            child: AppIconButton(
                              icon: FLucideIcons.x,
                              tooltip: l10n
                                  .watchlistSimulationRemovePositionAction(
                                    watchlistSimulationSymbolLabel(
                                      itemById[id],
                                      fallbackId: id,
                                    ),
                                  ),
                              onPress: () => _removePosition(id),
                              size: appActionTargetSize(context),
                              iconSize: AppIconSizes.sm,
                              surface: AppIconButtonSurface.softMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppActionButton(
                      variant: FButtonVariant.ghost,
                      mainAxisSize: MainAxisSize.min,
                      hapticIntent: AppInteractionIntent.select,
                      prefix: const Icon(
                        FLucideIcons.plus,
                        size: AppIconSizes.sm,
                      ),
                      onPress: () => unawaited(_addPositions()),
                      child: Flexible(
                        child: Text(l10n.watchlistSimulationAddPositionAction),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  PercentField(
                    key: const ValueKey<String>(
                      'watchlist-simulation-cash-weight',
                    ),
                    control: FTextFieldControl.managed(
                      controller: _cash,
                      onChange: (_) => setState(() {}),
                    ),
                    label: Text(l10n.watchlistSimulationCashField),
                    validator: (value) => _validatePercent(context, value),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Semantics(
                    key: _allocationSummaryKey,
                    liveRegion: true,
                    child: Text(
                      remaining == Decimal.zero
                          ? l10n.watchlistSimulationTotalReady
                          : _showAllocationError
                          ? l10n.watchlistSimulationWeightTotalError(
                              allocated.toString(),
                            )
                          : l10n.watchlistSimulationAllocatedSummary(
                              allocated.toString(),
                              remaining.toString(),
                            ),
                      key: const ValueKey<String>(
                        'watchlist-simulation-allocation-total',
                      ),
                      style: context.captionStyle.copyWith(
                        color: remaining == Decimal.zero
                            ? null
                            : context.theme.colors.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Decimal _percentOf(TextEditingController controller) =>
      Decimal.tryParse(controller.text.trim()) ?? Decimal.zero;

  Decimal _allocatedPercent() {
    var total = _percentOf(_cash);
    for (final id in _configured) {
      total += _percentOf(_weights[id]!);
    }
    return total.round(scale: 2);
  }

  void _removePosition(String itemId) {
    dirty.markDirty();
    setState(() {
      _configured.remove(itemId);
      _weights[itemId]!.text = '0';
    });
  }

  void _equalize() {
    final cash = _percentOf(_cash);
    final texts = watchlistSimulationSplitPercentTexts(
      ids: _configured,
      totalPercent: Decimal.fromInt(_kPercentScale) - cash,
    );
    dirty.markDirty();
    setState(() {
      for (final entry in texts.entries) {
        _weights[entry.key]!.text = entry.value;
      }
    });
  }

  void _fillCash() {
    var positions = Decimal.zero;
    for (final id in _configured) {
      positions += _percentOf(_weights[id]!);
    }
    final cash = Decimal.fromInt(_kPercentScale) - positions;
    if (cash < Decimal.zero) return;
    dirty.markDirty();
    setState(() => _cash.text = cash.round(scale: 2).toString());
  }

  Future<void> _addPositions() async {
    final l10n = AppLocalizations.of(context);
    final candidates = widget.items
        .where((item) => !_configured.contains(item.id))
        .toList(growable: false);
    if (candidates.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.info,
        l10n.watchlistSimulationAllSymbolsAdded,
      );
      return;
    }
    final picked = await showWatchlistSimulationSymbolPicker(
      context: context,
      items: candidates,
      title: l10n.watchlistSimulationPickSymbolsTitle,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    dirty.markDirty();
    setState(() => _configured.addAll(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (!_validateSimulationForm(_formKey)) return;
    final cash = _percentOf(_cash);
    final targetWeights = <String, Decimal>{};
    var total = cash;
    for (final id in _configured) {
      final percent = _percentOf(_weights[id]!);
      total += percent;
      if (percent > Decimal.zero) {
        targetWeights[id] = watchlistSimulationPercentToRatio(percent);
      }
    }
    total = total.round(scale: 2);
    if (total != Decimal.fromInt(_kPercentScale)) {
      setState(() => _showAllocationError = true);
      _revealSimulationField(_allocationSummaryKey.currentContext!);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    dirty.busy = true;
    try {
      final repository = await ref.read(
        watchlistSimulationRepositoryProvider.future,
      );
      final updated = await repository.updateDefinition(
        simulation: widget.simulation,
        name: _name.text,
        startingCapital: Decimal.parse(_capital.text.trim()),
      );
      await repository.replaceAllocation(
        simulation: updated,
        targetWeights: targetWeights,
        cashWeight: watchlistSimulationPercentToRatio(cash),
        holdingInputs: watchlistSimulationHoldingInputs(
          widget.items,
          widget.snapshots,
        ),
      );
      dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          _simulationSaveErrorMessage(error, l10n: l10n),
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Shared name field so create and edit validate identically.
class _WatchlistSimulationNameField extends StatelessWidget {
  const _WatchlistSimulationNameField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(l10n.watchlistSimulationNameField),
      validator: (value) {
        final name = value?.trim() ?? '';
        if (name.isEmpty) return l10n.watchlistSimulationNameRequired;
        if (name.length > kWatchlistSimulationNameMaxLength) {
          return l10n.watchlistSimulationNameTooLong(
            kWatchlistSimulationNameMaxLength,
          );
        }
        return null;
      },
    );
  }
}

/// Multi-select symbol list shared by the create page and the symbol picker.
class _WatchlistSimulationSymbolList extends StatefulWidget {
  const _WatchlistSimulationSymbolList({
    required this.items,
    required this.isSelected,
    required this.onToggle,
  });

  final List<WatchlistItem> items;
  final bool Function(String itemId) isSelected;
  final ValueChanged<String> onToggle;

  @override
  State<_WatchlistSimulationSymbolList> createState() =>
      _WatchlistSimulationSymbolListState();
}

class _WatchlistSimulationSymbolListState
    extends State<_WatchlistSimulationSymbolList> {
  static const int _searchThreshold = 8;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final visible = _query.isEmpty
        ? widget.items
        : widget.items
              .where((item) {
                final name = item.localizedName(languageCode) ?? '';
                return item.displaySymbol.toLowerCase().contains(_query) ||
                    name.toLowerCase().contains(_query);
              })
              .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.length > _searchThreshold) ...[
          FTextField(
            control: FTextFieldControl.managed(
              controller: _search,
              onChange: (value) =>
                  setState(() => _query = value.text.trim().toLowerCase()),
            ),
            hint: l10n.watchlistSimulationSearchSymbols,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        if (visible.isEmpty)
          Text(
            l10n.watchlistSimulationNoSearchResults,
            style: context.captionStyle,
          )
        else
          AppGroupedSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            child: Column(
              children: [
                for (final item in visible)
                  _WatchlistSimulationSymbolRow(
                    item: item,
                    selected: widget.isSelected(item.id),
                    onToggle: () => widget.onToggle(item.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WatchlistSimulationSymbolRow extends StatelessWidget {
  const _WatchlistSimulationSymbolRow({
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final WatchlistItem item;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final name = item.localizedName(
      Localizations.localeOf(context).languageCode,
    );
    return AppTappable(
      key: ValueKey<String>('watchlist-simulation-symbol-${item.id}'),
      onPress: onToggle,
      selected: selected,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: appActionTargetSize(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s6,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.displaySymbol, style: context.strongLabelStyle),
                    if (name != null)
                      Text(
                        name,
                        style: context.captionStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              FCheckbox(value: selected, onChange: (_) => onToggle()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight selection above the full-page allocation editor.
Future<Set<String>?> showWatchlistSimulationSymbolPicker({
  required BuildContext context,
  required List<WatchlistItem> items,
  required String title,
}) {
  return showAppFormSheet<Set<String>>(
    context: context,
    maxHeightFactor: 0.9,
    builder: (_) =>
        _WatchlistSimulationSymbolPickerSheet(items: items, title: title),
  );
}

class _WatchlistSimulationSymbolPickerSheet extends StatefulWidget {
  const _WatchlistSimulationSymbolPickerSheet({
    required this.items,
    required this.title,
  });

  final String title;

  final List<WatchlistItem> items;

  @override
  State<_WatchlistSimulationSymbolPickerSheet> createState() =>
      _WatchlistSimulationSymbolPickerSheetState();
}

class _WatchlistSimulationSymbolPickerSheetState
    extends State<_WatchlistSimulationSymbolPickerSheet> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: widget.title,
      footer: AppSheetFooter(
        cancelLabel: l10n.commonCancel,
        submitLabel: l10n.watchlistSimulationAddPositionAction,
        enabled: _selected.isNotEmpty,
        onSubmit: () => Navigator.of(context).pop(_selected),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.watchlistSimulationUniverseSummary(
              _selected.length,
              widget.items.length,
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          _WatchlistSimulationSymbolList(
            items: widget.items,
            isSelected: _selected.contains,
            onToggle: (itemId) => setState(() {
              if (!_selected.remove(itemId)) _selected.add(itemId);
            }),
          ),
        ],
      ),
    );
  }
}

String? _validatePercent(BuildContext context, String? value) {
  final parsed = Decimal.tryParse(value?.trim() ?? '');
  if (parsed == null ||
      parsed < Decimal.zero ||
      parsed > Decimal.fromInt(_kPercentScale)) {
    return AppLocalizations.of(context).watchlistSimulationInvalidWeight;
  }
  return null;
}

/// Surfaces the reason the write failed when it is one the user can fix,
/// instead of collapsing every failure into "could not save".
String _simulationSaveErrorMessage(
  Object error, {
  required AppLocalizations l10n,
}) {
  if (error is ArgumentError && error.name == 'name') {
    return l10n.watchlistSimulationNameTooLong(
      kWatchlistSimulationNameMaxLength,
    );
  }
  if (error is ArgumentError && error.name == 'startingCapital') {
    return l10n.watchlistSimulationCapitalRequired;
  }
  if (error is ArgumentError && error.name == 'allocationTotal') {
    return l10n.watchlistSimulationWeightTotalError(
      (error.invalidValue ?? '').toString(),
    );
  }
  return l10n.watchlistSimulationSaveFailed;
}
