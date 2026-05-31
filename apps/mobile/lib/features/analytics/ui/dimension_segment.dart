import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/equity_classification.dart';

/// Three-way picker for the active allocation dimension. Public so widget tests
/// can drive it without reaching into the page state.
class DimensionSegment extends StatelessWidget {
  const DimensionSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EquityAllocationDimension value;
  final ValueChanged<EquityAllocationDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<EquityAllocationDimension>(
      options: EquityAllocationDimension.values,
      value: value,
      labelOf: (dim) => switch (dim) {
        EquityAllocationDimension.sector => l10n.analyticsDimensionSector,
        EquityAllocationDimension.region => l10n.analyticsDimensionRegion,
        EquityAllocationDimension.marketCap => l10n.analyticsDimensionMarketCap,
      },
      iconOf: (dim) => switch (dim) {
        EquityAllocationDimension.sector => FLucideIcons.layoutGrid,
        EquityAllocationDimension.region => FLucideIcons.globe,
        EquityAllocationDimension.marketCap => FLucideIcons.chartColumn,
      },
      onChanged: (dim) {
        Haptics.selection();
        onChanged(dim);
      },
    );
  }
}
