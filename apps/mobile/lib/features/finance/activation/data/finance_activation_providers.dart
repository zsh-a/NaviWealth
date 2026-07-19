import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final confirmedImportCount = ref.watch(financeImportConfirmedProvider)
          ? 1
          : 0;
      if (confirmedImportCount == 0 || value.pending > 0) {
        return AsyncValue.data(
          buildFinanceActivation(
            confirmedImportCount: confirmedImportCount,
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
          confirmedImportCount: confirmedImportCount,
          pendingReviewCount: value.pending,
          runway: runway.requireValue,
        ),
      );
    });
