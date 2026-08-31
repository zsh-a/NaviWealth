import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_simulation_projection.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class WatchlistSimulationSection extends ConsumerWidget {
  const WatchlistSimulationSection({
    super.key,
    required this.collection,
    required this.items,
    required this.snapshots,
  });

  final WatchlistCollection collection;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final simulationsAsync = ref.watch(watchlistSimulationsProvider);
    return Column(
      key: const ValueKey<String>('watchlist-simulation-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.watchlistSimulationSectionTitle,
                style: context.labelStyle,
              ),
            ),
            FButton(
              variant: FButtonVariant.outline,
              onPress: items.isEmpty
                  ? null
                  : () => unawaited(
                      showWatchlistSimulationCreateSheet(
                        context: context,
                        collection: collection,
                        items: items,
                      ),
                    ),
              child: Text(l10n.watchlistSimulationCreateAction),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        simulationsAsync.whenOrLoading(
          context: context,
          loading: () => const AppGroupedSurface(
            child: Center(child: FCircularProgress()),
          ),
          error: (_, _) => AppGroupedSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.commonLoadFailed, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => ref.invalidate(watchlistSimulationsProvider),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
          data: (simulations) {
            final scoped = simulations
                .where((simulation) => simulation.collectionId == collection.id)
                .toList(growable: false);
            if (scoped.isEmpty) {
              return _WatchlistSimulationEmpty(itemsEmpty: items.isEmpty);
            }
            return Column(
              children: [
                for (var index = 0; index < scoped.length; index++) ...[
                  _WatchlistSimulationCard(
                    simulation: scoped[index],
                    items: items,
                    snapshots: snapshots,
                  ),
                  if (index != scoped.length - 1)
                    const SizedBox(height: AppSpacing.s8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WatchlistSimulationEmpty extends StatelessWidget {
  const _WatchlistSimulationEmpty({required this.itemsEmpty});

  final bool itemsEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppGroupedSurface(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemsEmpty
                ? l10n.watchlistSimulationNeedsSymbols
                : l10n.watchlistSimulationEmptyBody,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.watchlistSimulationIsolationNote,
            style: context.captionStyle,
          ),
        ],
      ),
    );
  }
}

class _WatchlistSimulationCard extends ConsumerWidget {
  const _WatchlistSimulationCard({
    required this.simulation,
    required this.items,
    required this.snapshots,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionsAsync = ref.watch(
      watchlistSimulationPositionsProvider(simulation.id),
    );
    return positionsAsync.whenOrLoading(
      context: context,
      loading: () =>
          const AppGroupedSurface(child: Center(child: FCircularProgress())),
      error: (_, _) => AppGroupedSurface(
        child: FButton(
          variant: FButtonVariant.outline,
          onPress: () => ref.invalidate(
            watchlistSimulationPositionsProvider(simulation.id),
          ),
          child: Text(AppLocalizations.of(context).commonRetry),
        ),
      ),
      data: (positions) => _WatchlistSimulationCardBody(
        simulation: simulation,
        positions: positions,
        items: items,
        snapshots: snapshots,
        onEdit: () => unawaited(
          showWatchlistSimulationAllocationSheet(
            context: context,
            simulation: simulation,
            positions: positions,
            items: items,
          ),
        ),
        onDelete: () => unawaited(_deleteSimulation(context, ref, simulation)),
      ),
    );
  }
}

class _WatchlistSimulationCardBody extends StatelessWidget {
  const _WatchlistSimulationCardBody({
    required this.simulation,
    required this.positions,
    required this.items,
    required this.snapshots,
    required this.onEdit,
    required this.onDelete,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationPosition> positions;
  final List<WatchlistItem> items;
  final List<WatchlistQuoteSnapshot> snapshots;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final itemById = {for (final item in items) item.id: item};
    final changesByItemId = <String, Decimal?>{
      for (final snapshot in snapshots)
        snapshot.item.id: snapshot.quote?.changePercent,
    };
    final projection = WatchlistSimulationProjection.calculate(
      positions: positions.map(
        (position) => WatchlistSimulationQuoteInput(
          watchlistItemId: position.watchlistItemId,
          targetWeight: position.targetWeight,
          changePercent: changesByItemId[position.watchlistItemId],
        ),
      ),
      cashWeight: simulation.cashWeight,
    );
    final dailyMoveAmount = projection.dailyMoveAmount(
      simulation.startingCapital,
    );
    return AppGroupedSurface(
      key: ValueKey<String>('watchlist-simulation-${simulation.id}'),
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
                    Text(simulation.name, style: context.labelStyle),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      l10n.watchlistSimulationPaperBadge,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: FLucideIcons.slidersHorizontal,
                tooltip: l10n.watchlistSimulationAdjustAction,
                onPress: onEdit,
                size: appActionTargetSize(context),
                iconSize: AppIconSizes.sm,
                surface: AppIconButtonSurface.softMuted,
              ),
              const SizedBox(width: AppSpacing.s8),
              AppIconButton(
                icon: FLucideIcons.trash2,
                tooltip: l10n.watchlistSimulationDeleteAction,
                onPress: onDelete,
                size: appActionTargetSize(context),
                iconSize: AppIconSizes.sm,
                surface: AppIconButtonSurface.softMuted,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistSimulationVirtualCapital,
                value: formatters.compactCurrency(
                  simulation.startingCapital,
                  code: simulation.baseCurrency,
                ),
              ),
              AppMetricItem(
                label: l10n.watchlistSimulationDailyMove,
                value: formatters.signedPercent(
                  projection.weightedDailyChange.toDouble(),
                  decimalDigits: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistSimulationPricedWeight,
                value: formatters.percent(
                  projection.pricedWeight.toDouble(),
                  decimalDigits: 0,
                ),
              ),
              AppMetricItem(
                label: l10n.watchlistSimulationCashWeight,
                value: formatters.percent(
                  simulation.cashWeight.toDouble(),
                  decimalDigits: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.watchlistSimulationDailyMoveAmount(
              formatters.signedMoney(
                dailyMoveAmount,
                unit: simulation.baseCurrency,
              ),
            ),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          const AppDivider(horizontalPadding: 0),
          const SizedBox(height: AppSpacing.s10),
          for (var index = 0; index < positions.length; index++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    itemById[positions[index].watchlistItemId]?.displaySymbol ??
                        _symbolFromId(positions[index].watchlistItemId),
                    style: context.captionStyle,
                  ),
                ),
                Text(
                  formatters.percent(
                    positions[index].targetWeight.toDouble(),
                    decimalDigits: 2,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
            if (index != positions.length - 1)
              const SizedBox(height: AppSpacing.s4),
          ],
          const SizedBox(height: AppSpacing.s10),
          Text(l10n.watchlistSimulationMethodNote, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.watchlistSimulationIsolationNote,
            style: context.captionStyle,
          ),
        ],
      ),
    );
  }
}

Future<void> showWatchlistSimulationCreateSheet({
  required BuildContext context,
  required WatchlistCollection collection,
  required List<WatchlistItem> items,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context).watchlistSimulationCreateTitle,
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistSimulationCreateSheet(
        collection: collection,
        items: items,
        dirty: dirty,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistSimulationCreateSheet extends ConsumerStatefulWidget {
  const _WatchlistSimulationCreateSheet({
    required this.collection,
    required this.items,
    required this.dirty,
  });

  final WatchlistCollection collection;
  final List<WatchlistItem> items;
  final FormDirtyController dirty;

  @override
  ConsumerState<_WatchlistSimulationCreateSheet> createState() =>
      _WatchlistSimulationCreateSheetState();
}

class _WatchlistSimulationCreateSheetState
    extends ConsumerState<_WatchlistSimulationCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _capital;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _capital = TextEditingController(text: '100000');
    widget.dirty.bindTextControllers([_name, _capital]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty && !widget.dirty.isDirty) {
      _name.text = AppLocalizations.of(context)
          .watchlistSimulationDefaultName(widget.collection.name);
      widget.dirty.snapshotBaseline();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _capital.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.watchlistSimulationIsolationNote,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.watchlistSimulationNameField),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? l10n.watchlistSimulationNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _capital),
            label: Text(l10n.watchlistSimulationCapitalField(baseCurrency)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: (value) {
              final capital = Decimal.tryParse(value?.trim() ?? '');
              return capital == null || capital <= Decimal.zero
                  ? l10n.watchlistInvalidNumber
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.watchlistSimulationEqualWeightNote(widget.items.length),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: l10n.watchlistSimulationCreateAction,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        watchlistSimulationRepositoryProvider.future,
      );
      await repository.create(
        collectionId: widget.collection.id,
        name: _name.text,
        baseCurrency: ref.read(baseCurrencyProvider),
        startingCapital: Decimal.parse(_capital.text.trim()),
        targetWeights: equalWatchlistSimulationWeights(
          widget.items.map((item) => item.id),
        ),
        cashWeight: Decimal.zero,
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).watchlistSimulationSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> showWatchlistSimulationAllocationSheet({
  required BuildContext context,
  required WatchlistSimulation simulation,
  required List<WatchlistSimulationPosition> positions,
  required List<WatchlistItem> items,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context).watchlistSimulationAdjustTitle,
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistSimulationAllocationSheet(
        simulation: simulation,
        positions: positions,
        items: items,
        dirty: dirty,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistSimulationAllocationSheet extends ConsumerStatefulWidget {
  const _WatchlistSimulationAllocationSheet({
    required this.simulation,
    required this.positions,
    required this.items,
    required this.dirty,
  });

  final WatchlistSimulation simulation;
  final List<WatchlistSimulationPosition> positions;
  final List<WatchlistItem> items;
  final FormDirtyController dirty;

  @override
  ConsumerState<_WatchlistSimulationAllocationSheet> createState() =>
      _WatchlistSimulationAllocationSheetState();
}

class _WatchlistSimulationAllocationSheetState
    extends ConsumerState<_WatchlistSimulationAllocationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _weights;
  late final TextEditingController _cash;
  bool _saving = false;
  String? _totalError;

  @override
  void initState() {
    super.initState();
    final existing = {
      for (final position in widget.positions)
        position.watchlistItemId: position.targetWeight,
    };
    final ids = <String>{
      ...existing.keys,
      ...widget.items.map((item) => item.id),
    };
    _weights = {
      for (final id in ids)
        id: TextEditingController(
          text: ((existing[id] ?? Decimal.zero) * Decimal.fromInt(100))
              .toString(),
        ),
    };
    _cash = TextEditingController(
      text: (widget.simulation.cashWeight * Decimal.fromInt(100)).toString(),
    );
    widget.dirty.bindTextControllers([..._weights.values, _cash]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    for (final controller in _weights.values) {
      controller.dispose();
    }
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemById = {for (final item in widget.items) item.id: item};
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.watchlistSimulationAllocationNote,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          for (final entry in _weights.entries) ...[
            FTextFormField(
              key: ValueKey<String>('watchlist-simulation-weight-${entry.key}'),
              control: FTextFieldControl.managed(controller: entry.value),
              label: Text(
                l10n.watchlistSimulationWeightField(
                  itemById[entry.key]?.displaySymbol ??
                      _symbolFromId(entry.key),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: _validatePercent,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          FTextFormField(
            key: const ValueKey<String>('watchlist-simulation-cash-weight'),
            control: FTextFieldControl.managed(controller: _cash),
            label: Text(l10n.watchlistSimulationCashField),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validatePercent,
          ),
          if (_totalError != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              _totalError!,
              style: context.captionStyle.copyWith(
                color: context.theme.colors.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: l10n.commonSave,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  String? _validatePercent(String? value) {
    final parsed = Decimal.tryParse(value?.trim() ?? '');
    if (parsed == null ||
        parsed < Decimal.zero ||
        parsed > Decimal.fromInt(100)) {
      return AppLocalizations.of(context).watchlistSimulationInvalidWeight;
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hundred = Decimal.fromInt(100);
    final targetWeights = <String, Decimal>{};
    var totalPercent = Decimal.parse(_cash.text.trim());
    for (final entry in _weights.entries) {
      final percent = Decimal.parse(entry.value.text.trim());
      totalPercent += percent;
      if (percent > Decimal.zero) {
        targetWeights[entry.key] = (percent / hundred).toDecimal(
          scaleOnInfinitePrecision: 8,
        );
      }
    }
    if (totalPercent != hundred) {
      setState(() {
        _totalError = AppLocalizations.of(context)
            .watchlistSimulationWeightTotalError(totalPercent.toString());
      });
      return;
    }
    setState(() {
      _saving = true;
      _totalError = null;
    });
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        watchlistSimulationRepositoryProvider.future,
      );
      await repository.replaceAllocation(
        simulation: widget.simulation,
        targetWeights: targetWeights,
        cashWeight: (Decimal.parse(_cash.text.trim()) / hundred).toDecimal(
          scaleOnInfinitePrecision: 8,
        ),
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).watchlistSimulationSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> _deleteSimulation(
  BuildContext context,
  WidgetRef ref,
  WatchlistSimulation simulation,
) async {
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
  try {
    final repository = await ref.read(
      watchlistSimulationRepositoryProvider.future,
    );
    await repository.delete(simulation);
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.watchlistSimulationSaveFailed,
      );
    }
  }
}

String _symbolFromId(String id) {
  final separator = id.indexOf(':');
  return separator < 0 ? id : id.substring(separator + 1);
}
