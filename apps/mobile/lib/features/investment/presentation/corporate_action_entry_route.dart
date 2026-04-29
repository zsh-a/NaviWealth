import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../domain/models/lot.dart';
import 'corporate_action_entry_page.dart';

/// Stub host for [CorporateActionEntryPage] until the holdings layer
/// (FIR-19 schema + sync) is wired up. The form needs a concrete asset
/// list and a way to look up open lots; this route hands it a single
/// in-memory holding so the flow is reachable end-to-end and the user can
/// see a live preview.
///
/// Once the real holdings repository exists, swap this for a Riverpod
/// consumer that pulls from it. The page itself is unchanged.
class CorporateActionEntryRoute extends StatelessWidget {
  const CorporateActionEntryRoute({super.key});

  static final List<CorporateActionAsset> _demoAssets = [
    const CorporateActionAsset(
      id: 'AAPL',
      displayName: 'Apple Inc. (AAPL)',
      accountId: 'demo-brokerage',
      currency: 'USD',
    ),
  ];

  static List<Lot> _demoLots(String assetId) {
    if (assetId != 'AAPL') return const [];
    return [
      Lot(
        id: 'demo-lot-1',
        openingTransactionId: 'demo-tx-1',
        accountId: 'demo-brokerage',
        assetId: 'AAPL',
        currency: 'USD',
        originalQuantity: Decimal.fromInt(100),
        remainingQuantity: Decimal.fromInt(100),
        costPerUnit: Decimal.parse('150'),
        openedAt: DateTime.utc(2025, 1, 15),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CorporateActionEntryPage(
      assets: _demoAssets,
      lotsForAsset: _demoLots,
      onSubmit: (preview) {
        // Persistence is a separate layer (Drift) — for now the snackbar in
        // the page is feedback enough.
      },
    );
  }
}
