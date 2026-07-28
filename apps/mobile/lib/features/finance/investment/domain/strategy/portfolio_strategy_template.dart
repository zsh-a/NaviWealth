import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

import 'portfolio_strategy.dart';

/// Single source of truth for creating and presenting a strategy type.
///
/// Built-in and user-authored types share this contract. Built-ins are
/// compile-time constants; custom types are synced rows with a [sync] value.
class PortfolioStrategyTemplate {
  const PortfolioStrategyTemplate({
    required this.kind,
    required this.localizedNames,
    required this.iconToken,
    required this.schemaVersion,
    required this.defaultCapitalRole,
    required this.defaultSettings,
    required this.defaultInternalTarget,
    required this.defaultDriftBandBps,
    required this.defaultTransferPolicy,
    required this.createdAt,
    required this.archived,
    required this.sync,
  });

  final PortfolioStrategyKind kind;
  final Map<String, String> localizedNames;
  final String iconToken;
  final int schemaVersion;
  final StrategyCapitalRole defaultCapitalRole;
  final PortfolioStrategySettings defaultSettings;
  final TargetAllocation defaultInternalTarget;
  final int defaultDriftBandBps;
  final GroupTransferPolicy defaultTransferPolicy;
  final DateTime? createdAt;
  final bool archived;
  final SyncMeta? sync;

  bool get isBuiltIn => sync == null;

  String displayName(String languageCode) =>
      localizedNames[languageCode] ??
      localizedNames['en'] ??
      localizedNames.values.firstOrNull ??
      kind.wire;

  void validate() {
    if (kind.wire.trim().isEmpty ||
        localizedNames.values.every((name) => name.trim().isEmpty) ||
        iconToken.trim().isEmpty ||
        schemaVersion <= 0 ||
        defaultDriftBandBps < 0 ||
        defaultDriftBandBps > 10000 ||
        !defaultInternalTarget.isValid) {
      throw const FormatException('Invalid portfolio strategy template.');
    }
  }

  PortfolioStrategyTemplate copyWith({
    Map<String, String>? localizedNames,
    String? iconToken,
    TargetAllocation? defaultInternalTarget,
    int? defaultDriftBandBps,
    GroupTransferPolicy? defaultTransferPolicy,
    bool? archived,
    SyncMeta? sync,
  }) {
    return PortfolioStrategyTemplate(
      kind: kind,
      localizedNames: localizedNames ?? this.localizedNames,
      iconToken: iconToken ?? this.iconToken,
      schemaVersion: schemaVersion,
      defaultCapitalRole: defaultCapitalRole,
      defaultSettings: defaultSettings,
      defaultInternalTarget:
          defaultInternalTarget ?? this.defaultInternalTarget,
      defaultDriftBandBps: defaultDriftBandBps ?? this.defaultDriftBandBps,
      defaultTransferPolicy:
          defaultTransferPolicy ?? this.defaultTransferPolicy,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      sync: sync ?? this.sync,
    );
  }
}

const kIndexCoreStrategyTemplate = PortfolioStrategyTemplate(
  kind: PortfolioStrategyKind.indexCore,
  localizedNames: {'en': 'Index core', 'zh': '指数核心'},
  iconToken: 'chart',
  schemaVersion: 1,
  defaultCapitalRole: StrategyCapitalRole.owner,
  defaultSettings: IndexCoreStrategySettings(automaticContributions: false),
  defaultInternalTarget: TargetAllocation(weights: {AssetCategory.etf: 1}),
  defaultDriftBandBps: 500,
  defaultTransferPolicy: GroupTransferPolicy.bidirectional,
  createdAt: null,
  archived: false,
  sync: null,
);

const kDividendIncomeStrategyTemplate = PortfolioStrategyTemplate(
  kind: PortfolioStrategyKind.dividendIncome,
  localizedNames: {'en': 'Dividend income', 'zh': '股息组合'},
  iconToken: 'income',
  schemaVersion: 1,
  defaultCapitalRole: StrategyCapitalRole.owner,
  defaultSettings: DividendIncomeStrategySettings(
    reinvestDividends: false,
    preservePositions: true,
  ),
  defaultInternalTarget: TargetAllocation(
    weights: {AssetCategory.stock: 0.5, AssetCategory.etf: 0.5},
  ),
  defaultDriftBandBps: 500,
  defaultTransferPolicy: GroupTransferPolicy.inflowsOnly,
  createdAt: null,
  archived: false,
  sync: null,
);

const kOptionsIncomeStrategyTemplate = PortfolioStrategyTemplate(
  kind: PortfolioStrategyKind.optionsIncome,
  localizedNames: {'en': 'Options income', 'zh': '期权收益'},
  iconToken: 'shield',
  schemaVersion: 1,
  defaultCapitalRole: StrategyCapitalRole.owner,
  defaultSettings: OptionsIncomeStrategySettings(
    protectCollateral: true,
    useOwnerProfile: true,
  ),
  defaultInternalTarget: TargetAllocation(
    weights: {AssetCategory.stock: 0.4, AssetCategory.cash: 0.6},
  ),
  defaultDriftBandBps: 500,
  defaultTransferPolicy: GroupTransferPolicy.isolated,
  createdAt: null,
  archived: false,
  sync: null,
);

const kBuiltInPortfolioStrategyTemplates = [
  kIndexCoreStrategyTemplate,
  kDividendIncomeStrategyTemplate,
  kOptionsIncomeStrategyTemplate,
];
