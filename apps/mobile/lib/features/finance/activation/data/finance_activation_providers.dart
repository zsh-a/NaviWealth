import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/providers.dart';
import '../../ingest/data/providers.dart';
import '../../runway/data/money_runway_providers.dart';
import '../domain/finance_activation.dart';
import 'finance_activation_store.dart';

final financeActivationProvider =
    Provider.autoDispose<AsyncValue<FinanceActivationSnapshot>>((ref) {
      final progress = ref.watch(ingestDraftProgressProvider);
      if (progress.isLoading) return const AsyncValue.loading();
      if (progress.hasError) {
        return AsyncValue.error(progress.error!, progress.stackTrace!);
      }
      final value = progress.requireValue;
      final importConfirmed = ref.watch(financeImportConfirmedProvider);
      final accounts = ref.watch(accountsStreamProvider);
      final entries = ref.watch(journalEntriesWithPostingsStreamProvider);
      if (!importConfirmed &&
          ((accounts.isLoading && !accounts.hasValue) ||
              (entries.isLoading && !entries.hasValue))) {
        return const AsyncValue.loading();
      }
      if (accounts.hasError) {
        return AsyncValue.error(accounts.error!, accounts.stackTrace!);
      }
      if (entries.hasError) {
        return AsyncValue.error(entries.error!, entries.stackTrace!);
      }
      final hasManualLedgerData =
          (accounts.value?.isNotEmpty ?? false) &&
          (entries.value?.isNotEmpty ?? false);
      final hasLedgerData = importConfirmed || hasManualLedgerData;
      if (!hasLedgerData || value.pending > 0) {
        return AsyncValue.data(
          buildFinanceActivation(
            hasLedgerData: hasLedgerData,
            pendingReviewCount: value.pending,
            runway: null,
          ),
        );
      }
      final runway = ref.watch(moneyRunwayProvider);
      if (runway.isLoading) return const AsyncValue.loading();
      if (runway.hasError) {
        return AsyncValue.error(runway.error!, runway.stackTrace!);
      }
      return AsyncValue.data(
        buildFinanceActivation(
          hasLedgerData: hasLedgerData,
          pendingReviewCount: value.pending,
          runway: runway.requireValue,
        ),
      );
    });
