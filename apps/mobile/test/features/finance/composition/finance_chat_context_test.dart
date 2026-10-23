import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/composition/finance_chat_context.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/fire/data/fire_plan_repository.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';
import '../data/repositories/_stub_stamper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('classifies current Finance routes and rejects obsolete prefixes', () {
    final cases = <String, String>{
      FinanceRoutes.home: 'home',
      FinanceRoutes.planFire: 'fire',
      '${FinanceRoutes.planFire}?scenario=live': 'fire',
      FinanceRoutes.wealthPortfolioStudioFor('p1'): 'investment',
      FinanceRoutes.wealthWatchlistSimulationsFor('c1'): 'investment',
      FinanceRoutes.wealthAccount('a1'): 'account',
      FinanceRoutes.wealthLiability('l1'): 'liability',
      FinanceRoutes.spending: 'expense',
      FinanceRoutes.expenseNew: 'expense',
      FinanceRoutes.expense('e1'): 'expense',
      FinanceRoutes.cashflowRecurring: 'activity',
      FinanceRoutes.planRebalance: 'plan',
      '/fire': 'global',
      '/investment': 'global',
      '/wealth/portfolios': 'wealth',
    };
    for (final entry in cases.entries) {
      expect(financeChatRouteArea(entry.key), entry.value, reason: entry.key);
    }
  });

  for (final currency in ['JPY', 'KWD']) {
    test(
      'Finance context keeps $currency units and never starts holdings',
      () async {
        SharedPreferences.setMockInitialValues({
          'naviwealth.settings.base_currency': currency,
          'naviwealth.preferences.risk_appetite': 'custom',
        });
        final preferences = await SharedPreferences.getInstance();
        final db = makeTestDatabase();
        addTearDown(db.close);
        final outbox = InMemoryOutboxStore();
        final stamper = makeStubStamper();
        final accounts = AccountRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
        );
        final plans = FirePlanRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
        );
        await accounts.create(
          type: AccountCategory.bank,
          name: 'Private account',
          currency: currency,
        );
        await accounts.create(
          type: AccountCategory.cash,
          name: 'Archived',
          currency: currency,
          archived: true,
        );
        final otherAccounts = AccountRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(userId: 'other-owner'),
        );
        await otherAccounts.create(
          type: AccountCategory.bank,
          name: 'Another owner',
          currency: currency,
        );
        await plans.upsert(
          FirePlan.unset(baseCurrency: currency)
              .copyWith(targetNetWorth: Decimal.parse('1234.567')),
        );
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            currentUserIdProvider.overrideWithValue(() async => 'u-test'),
            accountRepositoryProvider.overrideWith((ref) async => accounts),
            firePlanRepositoryProvider.overrideWith((ref) async => plans),
          ],
        );
        addTearDown(container.dispose);
        // Keep the source stream alive as the FIRE surface would.
        final subscription = container.listen(
          persistedFirePlanProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        await container.read(persistedFirePlanProvider.future);
        final contextProvider = FutureProvider(
          (ref) => buildFinanceChatContextBlocks(
            ref,
            const AiContext(
              path: FinanceRoutes.planFire,
              domain: DomainScope.finance,
            ),
          ),
        );

        final blocks = await container.read(contextProvider.future);

        final block = blocks.single;
        expect(block.metadata['trusted_as_instruction'], isFalse);
        final content = block.content! as Map<String, Object?>;
        expect(content['base_currency'], currency);
        expect(content['risk_preference'], 'custom');
        expect(content['route_area'], 'fire');
        expect(content['accounts'], {
          'total_count': 1,
          'by_kind': {'bank': 1},
        });
        expect(content['fire_goal'], {
          'target_amount': '1234.567',
          'currency': currency,
        });
        expect(jsonEncode(block.toJson()), isNot(contains('Private account')));
        expect(container.exists(holdingsSnapshotProvider), isFalse);
        expect(container.exists(dashboardSnapshotProvider), isFalse);
        expect(container.exists(fireDashboardViewProvider), isFalse);
      },
    );
  }
}
