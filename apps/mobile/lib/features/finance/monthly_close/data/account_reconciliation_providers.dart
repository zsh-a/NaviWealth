import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../accounts/data/account_balances_provider.dart';
import '../../data/repositories/providers.dart';
import '../../domain/models/enums.dart';
import '../domain/account_reconciliation.dart';
import 'account_reconciliation_repository.dart';

final accountReconciliationRepositoryProvider =
    FutureProvider<AccountReconciliationRepository>((ref) async {
      return AccountReconciliationRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

final reconciliationsForPeriodProvider = StreamProvider.autoDispose
    .family<List<AccountReconciliation>, String>((ref, periodMonth) async* {
      final repository = await ref.watch(
        accountReconciliationRepositoryProvider.future,
      );
      yield* repository.watchPeriod(periodMonth);
    });

final reconciliationTargetsForPeriodProvider = Provider.autoDispose
    .family<AsyncValue<List<ReconciliationTarget>>, String>((ref, periodMonth) {
      final accounts = ref.watch(allAccountsStreamProvider);
      final balances = ref.watch(accountBalancesByIdProvider);
      final reconciliations = ref.watch(
        reconciliationsForPeriodProvider(periodMonth),
      );
      if (accounts.isLoading ||
          balances.isLoading ||
          reconciliations.isLoading) {
        return const AsyncValue.loading();
      }
      final error = accounts.error ?? balances.error ?? reconciliations.error;
      if (error != null) return AsyncValue.error(error, StackTrace.current);
      final byFact = <String, AccountReconciliation>{
        for (final row in reconciliations.requireValue)
          '${row.accountId}\u0000${row.unit}': row,
      };
      final targets = <ReconciliationTarget>[];
      for (final account in accounts.requireValue) {
        if (account.archived || !_isReconciliable(account.type)) continue;
        final unit = account.currency.toUpperCase();
        targets.add(
          ReconciliationTarget(
            accountId: account.id,
            accountName: account.name,
            unit: unit,
            ledgerBalance:
                balances.requireValue[account.id]?.legFor(unit)?.units ??
                Decimal.zero,
            reconciliation: byFact['${account.id}\u0000$unit'],
          ),
        );
      }
      targets.sort((a, b) => a.accountName.compareTo(b.accountName));
      return AsyncValue.data(List.unmodifiable(targets));
    });

bool _isReconciliable(AccountCategory category) => switch (category) {
  AccountCategory.cash ||
  AccountCategory.bank ||
  AccountCategory.credit => true,
  _ => false,
};
