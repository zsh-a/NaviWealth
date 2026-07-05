import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'rebalance_models.dart';

/// Built-in allocation scheme presets.
enum AllocationSchemePreset { conservative, balanced, aggressive, custom }

/// Returns the default target weights for a preset scheme.
TargetAllocation allocationScheme(AllocationSchemePreset preset) {
  switch (preset) {
    case AllocationSchemePreset.conservative:
      return const TargetAllocation(
        weights: {
          AssetCategory.stock: 0.20,
          AssetCategory.etf: 0.10,
          AssetCategory.bondsAndFunds: 0.40,
          AssetCategory.cash: 0.20,
          AssetCategory.crypto: 0.00,
          AssetCategory.realEstate: 0.10,
          AssetCategory.vehicle: 0.00,
        },
      );
    case AllocationSchemePreset.balanced:
      return const TargetAllocation(
        weights: {
          AssetCategory.stock: 0.35,
          AssetCategory.etf: 0.15,
          AssetCategory.bondsAndFunds: 0.20,
          AssetCategory.cash: 0.10,
          AssetCategory.crypto: 0.05,
          AssetCategory.realEstate: 0.10,
          AssetCategory.vehicle: 0.05,
        },
      );
    case AllocationSchemePreset.aggressive:
      return const TargetAllocation(
        weights: {
          AssetCategory.stock: 0.50,
          AssetCategory.etf: 0.15,
          AssetCategory.bondsAndFunds: 0.10,
          AssetCategory.cash: 0.05,
          AssetCategory.crypto: 0.15,
          AssetCategory.realEstate: 0.05,
          AssetCategory.vehicle: 0.00,
        },
      );
    case AllocationSchemePreset.custom:
      // Custom starts from balanced as a template.
      return allocationScheme(AllocationSchemePreset.balanced);
  }
}
