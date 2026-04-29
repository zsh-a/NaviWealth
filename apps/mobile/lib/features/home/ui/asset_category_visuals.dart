import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/dashboard_models.dart';

/// Display helpers for [AssetCategory]: localized label + signature icon
/// shown on legend chips and drill-down headers. Colors come from the
/// [ChartPalette] accents so the pie slice and the legend chip stay in
/// sync without requiring a per-category color override.
class AssetCategoryVisuals {
  const AssetCategoryVisuals._();

  static String label(AppLocalizations l10n, AssetCategory category) {
    switch (category) {
      case AssetCategory.stock:
        return l10n.dashboardCategoryStock;
      case AssetCategory.etf:
        return l10n.dashboardCategoryEtf;
      case AssetCategory.bondsAndFunds:
        return l10n.dashboardCategoryBondsAndFunds;
      case AssetCategory.cash:
        return l10n.dashboardCategoryCash;
      case AssetCategory.crypto:
        return l10n.dashboardCategoryCrypto;
      case AssetCategory.realEstate:
        return l10n.dashboardCategoryRealEstate;
      case AssetCategory.vehicle:
        return l10n.dashboardCategoryVehicle;
      case AssetCategory.liability:
        return l10n.dashboardCategoryLiability;
    }
  }

  static IconData icon(AssetCategory category) {
    switch (category) {
      case AssetCategory.stock:
        return Icons.show_chart;
      case AssetCategory.etf:
        return Icons.candlestick_chart_outlined;
      case AssetCategory.bondsAndFunds:
        return Icons.savings_outlined;
      case AssetCategory.cash:
        return Icons.account_balance_wallet_outlined;
      case AssetCategory.crypto:
        return Icons.currency_bitcoin;
      case AssetCategory.realEstate:
        return Icons.home_outlined;
      case AssetCategory.vehicle:
        return Icons.directions_car_outlined;
      case AssetCategory.liability:
        return Icons.payments_outlined;
    }
  }
}
