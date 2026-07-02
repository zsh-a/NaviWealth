import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

String securitiesAssetTypeLabel(AppLocalizations l10n, AssetType t) {
  return switch (t) {
    AssetType.stock => l10n.assetTypeStock,
    AssetType.etf => l10n.assetTypeEtf,
    AssetType.mutualFund => l10n.assetTypeMutualFund,
    AssetType.bond => l10n.assetTypeBond,
    AssetType.crypto => l10n.assetTypeCrypto,
    _ => t.name,
  };
}

String manualAssetTypeLabel(AppLocalizations l10n, AssetType t) {
  return switch (t) {
    AssetType.cash => l10n.assetTypeCash,
    AssetType.bankDepositTerm => l10n.assetTypeBankDepositTerm,
    AssetType.bankDepositDemand => l10n.assetTypeBankDepositDemand,
    AssetType.wealthProduct => l10n.assetTypeWealthProduct,
    _ => t.name,
  };
}
