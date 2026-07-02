import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_fx_pnl_card.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/fx_pnl/fx_pnl_breakdown.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/holding_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

Decimal _d(String value) => Decimal.parse(value);

final _assetReport = AssetHoldingReport(
  assetId: 'us:AAPL',
  assetCurrency: 'USD',
  quantity: _d('12'),
  costBasisInAsset: _d('1500'),
  marketValueInAsset: _d('1920'),
  unrealizedPnlInAsset: _d('420'),
  costBasisAtOpenFxInBase: _d('10500'),
  marketValueInBase: _d('14208'),
  pnlBreakdown: FxPnLBreakdown(
    marketPnLInBase: _d('3108'),
    fxPnLInBase: _d('600'),
    baseCurrency: 'CNY',
  ),
  baseCurrency: 'CNY',
  asOf: DateTime.utc(2026, 5, 17),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runAllVariants('asset_fx_pnl_card', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'asset_fx_pnl_card',
      variant: variant,
      overrides: [
        assetHoldingReportProvider(
          'us:AAPL',
        ).overrideWith((_) async => _assetReport),
      ],
      child: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: AssetFxPnlCard(assetId: 'us:AAPL'),
          ),
        ),
      ),
    );
  });
}
