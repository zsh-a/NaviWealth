import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/resolver/price_resolver.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart';
import 'package:naviwealth/features/finance/market/domain/resolved_price.dart';

import 'support/integration_env.dart';

class _EmptyPriceResolver implements PriceResolver {
  const _EmptyPriceResolver();

  @override
  Future<ResolvedPrice?> resolve(Asset asset, {DateTime? asOf}) async => null;

  @override
  Future<Map<String, ResolvedPrice?>> resolveMany(
    Iterable<Asset> assets, {
    DateTime? asOf,
  }) async => {for (final asset in assets) asset.id: null};
}

void main() {
  test(
    'portfolio provider settles after its initial Drift hydration',
    () async {
      final env = await IntegrationEnv.create(
        extraOverrides: [
          priceResolverProvider.overrideWith(
            (_) async => const _EmptyPriceResolver(),
          ),
        ],
      );
      final transitions = <AsyncValue<PortfolioHubState>>[];
      final subscription = env.container.listen<AsyncValue<PortfolioHubState>>(
        portfolioHubProvider,
        (_, next) => transitions.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await env.container.read(portfolioHubProvider.future);
      await Future<void>.delayed(const Duration(seconds: 1));

      final firstData = transitions.indexWhere((value) => value.hasValue);
      expect(firstData, isNonNegative);
      final settledTransitionCount = transitions.length;

      await Future<void>.delayed(const Duration(seconds: 1));

      expect(transitions, hasLength(settledTransitionCount));
      expect(transitions.last, isA<AsyncData<PortfolioHubState>>());
    },
    tags: 'integration',
  );
}
