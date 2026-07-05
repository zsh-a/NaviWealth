import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/corporate_action_preview.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/lot.dart';
import 'corporate_action_entry_page.dart';

final _corporateActionLotsProvider = FutureProvider.autoDispose<List<Lot>>((
  ref,
) async {
  ref.watch(holdingsSnapshotProvider);
  final service = await ref.watch(holdingServiceProvider.future);
  return service.lotsAt(DateTime.now().toUtc());
});

/// Production host for [CorporateActionEntryPage].
///
/// The form remains a pure preview surface; this route supplies ledger-derived
/// holdings and persists submitted previews as balanced journal entries.
class CorporateActionEntryRoute extends ConsumerWidget {
  const CorporateActionEntryRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(allAssetsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final lotsAsync = ref.watch(_corporateActionLotsProvider);

    if (assetsAsync.isLoading ||
        accountsAsync.isLoading ||
        lotsAsync.isLoading) {
      return _ScaffoldMessage(
        title: l10n.corpActionTitle,
        child: const FCircularProgress(),
      );
    }
    final error = assetsAsync.error ?? accountsAsync.error ?? lotsAsync.error;
    if (error != null) {
      return _ScaffoldMessage(
        title: l10n.corpActionTitle,
        child: Text(l10n.commonLoadError('$error')),
      );
    }

    final assets = assetsAsync.value ?? const <Asset>[];
    final accounts = accountsAsync.value ?? const <Account>[];
    final lots = lotsAsync.value ?? const <Lot>[];
    final choices = _buildChoices(assets, accounts, lots);

    if (choices.isEmpty) {
      return _ScaffoldMessage(
        title: l10n.corpActionTitle,
        child: Text(l10n.corpActionNoEligibleHolding),
      );
    }

    return CorporateActionEntryPage(
      assets: choices,
      lotsForAsset: (asset) => lots
          .where(
            (lot) =>
                !lot.isClosed &&
                lot.assetId == asset.id &&
                lot.accountId == asset.accountId,
          )
          .toList(growable: false),
      onSubmit: (preview) {
        unawaited(_submitCorporateAction(context, ref, preview));
      },
    );
  }
}

class _ScaffoldMessage extends StatelessWidget {
  const _ScaffoldMessage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      child: Center(child: child),
    );
  }
}

List<CorporateActionAsset> _buildChoices(
  List<Asset> assets,
  List<Account> accounts,
  List<Lot> lots,
) {
  final assetsById = {for (final asset in assets) asset.id: asset};
  final accountsById = {for (final account in accounts) account.id: account};
  final seen = <String>{};
  final choices = <CorporateActionAsset>[];

  for (final lot in lots.where((l) => !l.isClosed)) {
    final key = '${lot.accountId}|${lot.assetId}';
    if (!seen.add(key)) continue;
    final asset = assetsById[lot.assetId];
    final account = accountsById[lot.accountId];
    final symbol = asset?.symbol ?? lot.assetId;
    final name = asset?.name;
    final accountName = account?.name ?? lot.accountId;
    final displayName = name == null || name.isEmpty
        ? '$symbol · $accountName'
        : '$name ($symbol) · $accountName';
    choices.add(
      CorporateActionAsset(
        id: lot.assetId,
        displayName: displayName,
        accountId: lot.accountId,
        currency: lot.currency,
      ),
    );
  }

  choices.sort((a, b) => a.displayName.compareTo(b.displayName));
  return choices;
}

Future<void> _submitCorporateAction(
  BuildContext context,
  WidgetRef ref,
  CorporateActionPreview preview,
) async {
  final l10n = AppLocalizations.of(context);
  final logger = ref.read(loggerProvider);
  final actionRepo = await ref.read(corporateActionRepositoryProvider.future);
  final jeRepo = await ref.read(journalEntryRepositoryProvider.future);
  final priceRepo = await ref.read(priceRepositoryProvider.future);
  final uid = await ref.read(currentUserIdProvider)();

  if (!context.mounted) return;
  AppMessenger.cacheOverlay(context);
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }

  await _runCorporateActionWrite(
    write: () => _persistPreview(
      preview,
      uid: uid,
      jeRepo: jeRepo,
      recordAction: actionRepo.upsert,
      recordPrice:
          ({
            required String unit,
            required String quoteCurrency,
            required DateTime observedOn,
            required Decimal perUnit,
            required String source,
          }) async {
            await priceRepo.record(
              unit: unit,
              quoteCurrency: quoteCurrency,
              observedOn: observedOn,
              perUnit: perUnit,
              source: source,
            );
          },
    ),
    failureMessage: l10n.commonSaveFailed,
    logger: logger,
    context: context,
    retryLabel: l10n.commonRetry,
  );
}

Future<void> _runCorporateActionWrite({
  required Future<void> Function() write,
  required String failureMessage,
  required AppLogger logger,
  required BuildContext context,
  required String retryLabel,
}) async {
  try {
    await write();
  } catch (error, stack) {
    logger.e(
      'optimistic-corporate-action write failed',
      error: error,
      stackTrace: stack,
    );
    AppMessenger.show(
      // ignore: use_build_context_synchronously -- overlay cached before pop.
      context,
      ToastKind.error,
      failureMessage,
      duration: const Duration(seconds: 6),
      actionLabel: retryLabel,
      onAction: () => _runCorporateActionWrite(
        write: write,
        failureMessage: failureMessage,
        logger: logger,
        context: context,
        retryLabel: retryLabel,
      ),
    );
  }
}

Future<void> _persistPreview(
  CorporateActionPreview preview, {
  required String uid,
  required JournalEntryRepository jeRepo,
  required Future<void> Function(CorporateAction action) recordAction,
  required Future<void> Function({
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
  })
  recordPrice,
}) async {
  final action = preview.action;
  switch (action) {
    case CashDividendAction a:
      final dividend = preview.cashDividend;
      if (dividend == null) return;
      final build = JournalEntryBuilders.dividend(
        date: a.effectiveDate,
        cashAccountId: a.accountId,
        incomeAccountId: AccountRepository.systemAccountIdForPath(
          'income:dividend',
          ownerUserId: uid,
        ),
        amount: dividend.grossAmount,
        currency: a.currency,
        withholdingAmount: _nonZero(dividend.withholdingTax),
        withholdingAccountId: dividend.withholdingTax == Decimal.zero
            ? null
            : AccountRepository.systemAccountIdForPath(
                'expense:tax:withholding',
                ownerUserId: uid,
              ),
        assetUnit: a.assetId,
        narration: 'Cash dividend',
      );
      await jeRepo.create(entry: build.entry, postings: build.postings);
    case DripAction a:
      final dividend = preview.cashDividend;
      final newLot = _singleOrNull(preview.newLots);
      if (dividend == null || newLot == null) return;
      final build = JournalEntryBuilders.drip(
        date: a.effectiveDate,
        accountId: a.accountId,
        incomeAccountId: AccountRepository.systemAccountIdForPath(
          'income:dividend',
          ownerUserId: uid,
        ),
        assetUnit: a.assetId,
        grossAmount: dividend.grossAmount,
        reinvestedQuantity: newLot.remainingQuantity,
        pricePerUnit: a.pricePerUnit,
        currency: a.currency,
        lotId: newLot.id,
        acquiredOn: newLot.openedAt,
        withholdingAmount: _nonZero(dividend.withholdingTax),
        withholdingAccountId: dividend.withholdingTax == Decimal.zero
            ? null
            : AccountRepository.systemAccountIdForPath(
                'expense:tax:withholding',
                ownerUserId: uid,
              ),
        feeAmount: _nonZero(a.fee),
        feeAccountId: a.fee == Decimal.zero
            ? null
            : AccountRepository.systemAccountIdForPath(
                'expense:trading:fee',
                ownerUserId: uid,
              ),
      );
      await jeRepo.create(entry: build.entry, postings: build.postings);
      await recordPrice(
        unit: a.assetId,
        quoteCurrency: a.currency,
        observedOn: a.effectiveDate,
        perUnit: a.pricePerUnit,
        source: 'drip',
      );
    case RightsIssueAction a:
      final newLot = _singleOrNull(preview.newLots);
      final build = JournalEntryBuilders.buy(
        date: a.effectiveDate,
        accountId: a.accountId,
        cashAccountId: a.accountId,
        assetUnit: a.assetId,
        qty: a.subscribedQuantity,
        price: a.pricePerUnit,
        quoteCurrency: a.currency,
        lotId: newLot?.id,
        acquiredOn: newLot?.openedAt,
        feeAmount: _nonZero(a.fee),
        feeAccountId: a.fee == Decimal.zero
            ? null
            : AccountRepository.systemAccountIdForPath(
                'expense:trading:fee',
                ownerUserId: uid,
              ),
        narration: 'Rights issue',
      );
      await jeRepo.create(entry: build.entry, postings: build.postings);
      await recordPrice(
        unit: a.assetId,
        quoteCurrency: a.currency,
        observedOn: a.effectiveDate,
        perUnit: a.pricePerUnit,
        source: 'rights',
      );
    case SplitAction a:
      await _persistLotAdjustments(
        preview,
        jeRepo: jeRepo,
        date: a.effectiveDate,
        assetUnit: a.assetId,
        narration: 'Split',
      );
    case StockDividendAction a:
      await _persistLotAdjustments(
        preview,
        jeRepo: jeRepo,
        date: a.effectiveDate,
        assetUnit: a.assetId,
        narration: 'Stock dividend',
      );
  }
  await recordAction(action);
}

Future<void> _persistLotAdjustments(
  CorporateActionPreview preview, {
  required JournalEntryRepository jeRepo,
  required DateTime date,
  required String assetUnit,
  required String narration,
}) async {
  var ordinal = 0;
  for (final delta in preview.lotDeltas) {
    ordinal++;
    final build = JournalEntryBuilders.lotAdjustment(
      date: date,
      accountId: delta.before.accountId,
      assetUnit: assetUnit,
      currency: delta.before.currency,
      beforeQuantity: delta.before.remainingQuantity,
      beforeCostPerUnit: delta.before.costPerUnit,
      afterQuantity: delta.after.remainingQuantity,
      afterCostPerUnit: delta.after.costPerUnit,
      oldLotId: delta.before.id,
      oldAcquiredOn: delta.before.openedAt,
      newLotId:
          '${delta.before.id}:corp:${date.millisecondsSinceEpoch}:$ordinal',
      narration: narration,
      tagIds: <String>['corp-action'],
    );
    await jeRepo.create(entry: build.entry, postings: build.postings);
  }
}

Decimal? _nonZero(Decimal value) => value == Decimal.zero ? null : value;

T? _singleOrNull<T>(List<T> values) =>
    values.length == 1 ? values.single : null;
