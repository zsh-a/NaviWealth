import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/l10n/gen/app_localizations.dart';
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
        return FLucideIcons.chartLine;
      case AssetCategory.etf:
        return FLucideIcons.candlestickChart;
      case AssetCategory.bondsAndFunds:
        return FLucideIcons.piggyBank;
      case AssetCategory.cash:
        return FLucideIcons.wallet;
      case AssetCategory.crypto:
        return FLucideIcons.bitcoin;
      case AssetCategory.realEstate:
        return FLucideIcons.house;
      case AssetCategory.vehicle:
        return FLucideIcons.car;
      case AssetCategory.liability:
        return FLucideIcons.banknote;
    }
  }
}
