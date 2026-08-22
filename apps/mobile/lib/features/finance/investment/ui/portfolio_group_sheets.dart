import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/forms/percent_input_formatter.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/ui/target_allocation_editor_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
import 'capital_allocation_plan_editor.dart';
import 'portfolio_removal_feedback.dart';
import 'portfolio_strategy_visuals.dart';
import 'removal_transfer_sheet.dart';

part 'portfolio_groups/group_forms.dart';
part 'portfolio_groups/section.dart';
part 'portfolio_groups/strategy_library.dart';
part 'portfolio_groups/strategy_template_form.dart';

String? _validatePercent(String? value, AppLocalizations l10n) {
  final parsed = double.tryParse(value?.trim() ?? '');
  return parsed == null || parsed < 0 || parsed > 100
      ? l10n.targetAllocationEditorRangeError
      : null;
}

int _bpsFromPercent(String value) => (double.parse(value.trim()) * 100).round();

String _percentFromBps(int value) {
  final percent = value / 100;
  return percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(2);
}

String _transferPolicyLabel(AppLocalizations l10n, GroupTransferPolicy policy) {
  return switch (policy) {
    GroupTransferPolicy.bidirectional =>
      l10n.portfolioGroupTransferBidirectional,
    GroupTransferPolicy.inflowsOnly => l10n.portfolioGroupTransferInflowsOnly,
    GroupTransferPolicy.isolated => l10n.portfolioGroupTransferIsolated,
  };
}

String _assetCategoryLabel(AppLocalizations l10n, AssetCategory category) =>
    AssetCategoryVisuals.label(l10n, category);
