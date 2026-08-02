import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';

void main() {
  test('portfolio studio route preserves a typed capital transfer task', () {
    const intent = CapitalTransferIntent(
      fromPortfolioId: 'core',
      toPortfolioId: 'income',
      amount: '1250.50',
      currency: 'USD',
      fromGroupId: 'index',
      toGroupId: 'dividend',
    );

    final uri = Uri.parse(
      FinanceRoutes.wealthPortfolioStudioFor(
        'core',
        section: PortfolioStudioSection.assets,
        transfer: intent,
      ),
    );
    final decoded = CapitalTransferIntent.fromQuery(uri.queryParameters);

    expect(uri.path, '/wealth/portfolio/core/studio');
    expect(uri.queryParameters['section'], PortfolioStudioSection.assets.name);
    expect(decoded?.fromPortfolioId, intent.fromPortfolioId);
    expect(decoded?.toPortfolioId, intent.toPortfolioId);
    expect(decoded?.amount, intent.amount);
    expect(decoded?.currency, intent.currency);
    expect(decoded?.fromGroupId, intent.fromGroupId);
    expect(decoded?.toGroupId, intent.toGroupId);
  });

  test('portfolio assignment pages preserve optional workflow context', () {
    final lots = Uri.parse(
      FinanceRoutes.wealthPortfolioAssignLotsFor(
        preferredGroupId: 'core/sleeve',
      ),
    );
    final cash = Uri.parse(
      FinanceRoutes.wealthPortfolioAssignCashFor(
        preferredGroupId: 'income',
        suggestedAmount: '1250.50',
      ),
    );

    expect(lots.path, FinanceRoutes.wealthPortfolioAssignLots);
    expect(lots.queryParameters['group'], 'core/sleeve');
    expect(cash.path, FinanceRoutes.wealthPortfolioAssignCash);
    expect(cash.queryParameters['group'], 'income');
    expect(cash.queryParameters['amount'], '1250.50');
  });
}
