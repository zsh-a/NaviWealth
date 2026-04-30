import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/fx_rate.dart' as dom;
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';

/// Manual FX-rate management.
///
/// FIR-73 wires the dashboard converter to the local `fx_rates` Drift table
/// but until an external rate feed lands, the table is populated only by
/// this page. Showing the recorded rates next to an "add" form makes the
/// "X holdings excluded — missing FX rate" banner actionable instead of
/// purely informational.
///
/// The page is intentionally minimal: a list of stored rates, a FAB that
/// opens the entry sheet, and a swipe-to-delete affordance. We do NOT
/// validate the magnitude of the rate (USD/CNY of 0.5 is wrong but
/// plausible for a typo); the bottom sheet only enforces structural
/// invariants (positive value, distinct currencies).
class FxRatesPage extends ConsumerWidget {
  const FxRatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ratesAsync = ref.watch(fxRatesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.fxRatesAppBarTitle)),
      body: ratesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rates) => _RateList(rates: rates),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntrySheet(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.fxRatesAddAction),
      ),
    );
  }

  Future<void> _openEntrySheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: const _FxRateEntryForm(),
      ),
    );
  }
}

class _RateList extends ConsumerWidget {
  const _RateList({required this.rates});

  final List<dom.FxRate> rates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (rates.isEmpty) {
      return Padding(
        padding: Spacing.pageMobile,
        child: Center(
          child: Text(
            l10n.fxRatesEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    final dateFmt = DateFormat.yMMMd();
    // Most-recent first — manual entry order is rarely chronological.
    final ordered = [...rates]
      ..sort((a, b) => b.date.compareTo(a.date));
    return ListView.separated(
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final r = ordered[i];
        return Dismissible(
          key: ValueKey('${r.base}-${r.quote}-${r.date.toIso8601String()}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(ctx).colorScheme.errorContainer,
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
          ),
          confirmDismiss: (_) async {
            final repo = await ref.read(fxRateRepositoryProvider.future);
            await repo.deleteByNaturalKey(
              base: r.base,
              quote: r.quote,
              date: r.date,
            );
            return true;
          },
          child: ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text('1 ${r.base} = ${r.rate} ${r.quote}'),
            subtitle: Text(
              '${dateFmt.format(r.date)} · ${r.source}',
            ),
          ),
        );
      },
    );
  }
}

class _FxRateEntryForm extends ConsumerStatefulWidget {
  const _FxRateEntryForm();

  @override
  ConsumerState<_FxRateEntryForm> createState() => _FxRateEntryFormState();
}

class _FxRateEntryFormState extends ConsumerState<_FxRateEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  String? _from = 'USD';
  String? _to = 'CNY';
  DateTime _asOf = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_from == _to) {
      setState(() => _error = AppLocalizations.of(context).fxRatesSamePairError);
      return;
    }
    final rate = Decimal.tryParse(_rateController.text.trim());
    if (rate == null || rate <= Decimal.zero) {
      setState(() => _error = AppLocalizations.of(context).fxRatesInvalidRateError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(fxRateRepositoryProvider.future);
      await repo.upsertDaily(
        baseCurrency: _from!,
        quoteCurrency: _to!,
        rate: rate,
        asOf: _asOf,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s8,
          Spacing.s16,
          Spacing.s24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.s8),
                child: Text(
                  l10n.fxRatesEntrySheetTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              CurrencyPicker(
                label: l10n.fxRatesFromLabel,
                value: _from,
                onChanged: (v) => setState(() => _from = v),
              ),
              const SizedBox(height: Spacing.s12),
              CurrencyPicker(
                label: l10n.fxRatesToLabel,
                value: _to,
                onChanged: (v) => setState(() => _to = v),
              ),
              const SizedBox(height: Spacing.s12),
              AmountField(
                label: l10n.fxRatesRateLabel,
                controller: _rateController,
                helperText: _from == null || _to == null
                    ? null
                    : '1 $_from = ? $_to',
              ),
              const SizedBox(height: Spacing.s12),
              DateField(
                label: l10n.fxRatesAsOfLabel,
                initialValue: _asOf,
                required: true,
                onChanged: (d) {
                  if (d != null) setState(() => _asOf = d);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.s8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.s16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? l10n.commonLoading : l10n.commonSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
