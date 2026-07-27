import 'package:naviwealth/core/sync/sync_meta.dart';

/// Stable, open identifier for a portfolio strategy module.
///
/// A value object is intentional: independently-owned FinanceOS modules can
/// add identifiers without editing a central enum or collapsing unknown
/// synced values to "custom".
class PortfolioStrategyKind {
  const PortfolioStrategyKind(this.wire)
    : assert(wire != '', 'Strategy wire id must not be empty.');

  static const indexCore = PortfolioStrategyKind('index_core');
  static const dividendIncome = PortfolioStrategyKind('dividend_income');
  static const optionsIncome = PortfolioStrategyKind('options_income');

  final String wire;

  @override
  bool operator ==(Object other) =>
      other is PortfolioStrategyKind && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => wire;
}

PortfolioStrategyKind portfolioStrategyKindFromWire(String wire) {
  final normalized = wire.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Strategy wire id must not be empty.');
  }
  return PortfolioStrategyKind(normalized);
}

/// Whether a strategy owns capital or only overlays another capital group.
enum StrategyCapitalRole { owner, overlay }

/// Module-owned, strongly typed strategy settings.
abstract interface class PortfolioStrategySettings {
  const PortfolioStrategySettings();
}

class IndexCoreStrategySettings implements PortfolioStrategySettings {
  const IndexCoreStrategySettings({required this.automaticContributions});

  final bool automaticContributions;
}

class DividendIncomeStrategySettings implements PortfolioStrategySettings {
  const DividendIncomeStrategySettings({
    required this.reinvestDividends,
    required this.preservePositions,
  });

  final bool reinvestDividends;
  final bool preservePositions;
}

class OptionsIncomeStrategySettings implements PortfolioStrategySettings {
  const OptionsIncomeStrategySettings({
    required this.protectCollateral,
    required this.useOwnerProfile,
  });

  final bool protectCollateral;
  final bool useOwnerProfile;
}

/// Lossless value used when a newer module is present but not registered in
/// the running build. Unknown data remains round-trippable and is never
/// rewritten as another strategy kind.
class OpaquePortfolioStrategySettings implements PortfolioStrategySettings {
  const OpaquePortfolioStrategySettings(this.payload);

  final Map<String, Object?> payload;
}

class PortfolioStrategyConfig {
  const PortfolioStrategyConfig({
    required this.id,
    required this.portfolioId,
    required this.kind,
    required this.schemaVersion,
    required this.enabled,
    required this.capitalRole,
    required this.rebalanceGroupId,
    required this.settings,
    required this.sync,
  });

  final String id;
  final String portfolioId;
  final PortfolioStrategyKind kind;
  final int schemaVersion;
  final bool enabled;
  final StrategyCapitalRole capitalRole;
  final String? rebalanceGroupId;
  final PortfolioStrategySettings settings;
  final SyncMeta sync;

  PortfolioStrategyConfig copyWith({
    bool? enabled,
    StrategyCapitalRole? capitalRole,
    String? rebalanceGroupId,
    PortfolioStrategySettings? settings,
    SyncMeta? sync,
  }) {
    return PortfolioStrategyConfig(
      id: id,
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: schemaVersion,
      enabled: enabled ?? this.enabled,
      capitalRole: capitalRole ?? this.capitalRole,
      rebalanceGroupId: rebalanceGroupId ?? this.rebalanceGroupId,
      settings: settings ?? this.settings,
      sync: sync ?? this.sync,
    );
  }
}

abstract interface class PortfolioStrategyDefinition<
  C extends PortfolioStrategySettings
> {
  PortfolioStrategyKind get kind;
  int get currentSchemaVersion;
  StrategyCapitalRole get defaultCapitalRole;
  C get defaultSettings;

  C decode(Map<String, Object?> payload, int schemaVersion);
  Map<String, Object?> encode(C settings);
  List<String> validate(C settings);
}

class PortfolioStrategyRegistry {
  PortfolioStrategyRegistry(Iterable<PortfolioStrategyDefinition> definitions)
    : _definitions = {
        for (final definition in definitions) definition.kind: definition,
      };

  factory PortfolioStrategyRegistry.standard() =>
      PortfolioStrategyRegistry(const [
        IndexCoreStrategyDefinition(),
        DividendIncomeStrategyDefinition(),
        OptionsIncomeStrategyDefinition(),
      ]);

  final Map<PortfolioStrategyKind, PortfolioStrategyDefinition> _definitions;

  Iterable<PortfolioStrategyDefinition> get definitions => _definitions.values;

  PortfolioStrategyDefinition? definitionFor(PortfolioStrategyKind kind) =>
      _definitions[kind];

  PortfolioStrategySettings decode({
    required PortfolioStrategyKind kind,
    required int schemaVersion,
    required Map<String, Object?> payload,
  }) {
    final definition = definitionFor(kind);
    if (definition == null) {
      return OpaquePortfolioStrategySettings(Map.unmodifiable(payload));
    }
    return definition.decode(payload, schemaVersion);
  }

  Map<String, Object?> encode(
    PortfolioStrategyKind kind,
    PortfolioStrategySettings settings,
  ) {
    final definition = definitionFor(kind);
    if (definition == null) {
      if (settings is OpaquePortfolioStrategySettings) {
        return settings.payload;
      }
      throw StateError('No strategy definition registered for ${kind.wire}.');
    }
    return definition.encode(settings);
  }
}

class IndexCoreStrategyDefinition
    implements PortfolioStrategyDefinition<IndexCoreStrategySettings> {
  const IndexCoreStrategyDefinition();

  @override
  PortfolioStrategyKind get kind => PortfolioStrategyKind.indexCore;

  @override
  int get currentSchemaVersion => 1;

  @override
  StrategyCapitalRole get defaultCapitalRole => StrategyCapitalRole.owner;

  @override
  IndexCoreStrategySettings get defaultSettings =>
      const IndexCoreStrategySettings(automaticContributions: false);

  @override
  IndexCoreStrategySettings decode(
    Map<String, Object?> payload,
    int schemaVersion,
  ) {
    _requireVersion(kind, schemaVersion, currentSchemaVersion);
    _requireExactKeys(payload, const {'automatic_contributions'}, kind);
    return IndexCoreStrategySettings(
      automaticContributions: _requireBool(
        payload,
        'automatic_contributions',
        kind,
      ),
    );
  }

  @override
  Map<String, Object?> encode(IndexCoreStrategySettings settings) => {
    'automatic_contributions': settings.automaticContributions,
  };

  @override
  List<String> validate(IndexCoreStrategySettings settings) => const [];
}

class DividendIncomeStrategyDefinition
    implements PortfolioStrategyDefinition<DividendIncomeStrategySettings> {
  const DividendIncomeStrategyDefinition();

  @override
  PortfolioStrategyKind get kind => PortfolioStrategyKind.dividendIncome;

  @override
  int get currentSchemaVersion => 1;

  @override
  StrategyCapitalRole get defaultCapitalRole => StrategyCapitalRole.owner;

  @override
  DividendIncomeStrategySettings get defaultSettings =>
      const DividendIncomeStrategySettings(
        reinvestDividends: false,
        preservePositions: true,
      );

  @override
  DividendIncomeStrategySettings decode(
    Map<String, Object?> payload,
    int schemaVersion,
  ) {
    _requireVersion(kind, schemaVersion, currentSchemaVersion);
    _requireExactKeys(payload, const {
      'reinvest_dividends',
      'preserve_positions',
    }, kind);
    return DividendIncomeStrategySettings(
      reinvestDividends: _requireBool(payload, 'reinvest_dividends', kind),
      preservePositions: _requireBool(payload, 'preserve_positions', kind),
    );
  }

  @override
  Map<String, Object?> encode(DividendIncomeStrategySettings settings) => {
    'reinvest_dividends': settings.reinvestDividends,
    'preserve_positions': settings.preservePositions,
  };

  @override
  List<String> validate(DividendIncomeStrategySettings settings) => const [];
}

class OptionsIncomeStrategyDefinition
    implements PortfolioStrategyDefinition<OptionsIncomeStrategySettings> {
  const OptionsIncomeStrategyDefinition();

  @override
  PortfolioStrategyKind get kind => PortfolioStrategyKind.optionsIncome;

  @override
  int get currentSchemaVersion => 1;

  @override
  StrategyCapitalRole get defaultCapitalRole => StrategyCapitalRole.owner;

  @override
  OptionsIncomeStrategySettings get defaultSettings =>
      const OptionsIncomeStrategySettings(
        protectCollateral: true,
        useOwnerProfile: true,
      );

  @override
  OptionsIncomeStrategySettings decode(
    Map<String, Object?> payload,
    int schemaVersion,
  ) {
    _requireVersion(kind, schemaVersion, currentSchemaVersion);
    _requireExactKeys(payload, const {
      'protect_collateral',
      'use_owner_profile',
    }, kind);
    return OptionsIncomeStrategySettings(
      protectCollateral: _requireBool(payload, 'protect_collateral', kind),
      useOwnerProfile: _requireBool(payload, 'use_owner_profile', kind),
    );
  }

  @override
  Map<String, Object?> encode(OptionsIncomeStrategySettings settings) => {
    'protect_collateral': settings.protectCollateral,
    'use_owner_profile': settings.useOwnerProfile,
  };

  @override
  List<String> validate(OptionsIncomeStrategySettings settings) => const [];
}

void _requireVersion(PortfolioStrategyKind kind, int actual, int expected) {
  if (actual != expected) {
    throw FormatException(
      'Unsupported ${kind.wire} schema version $actual; expected $expected.',
    );
  }
}

void _requireExactKeys(
  Map<String, Object?> payload,
  Set<String> expected,
  PortfolioStrategyKind kind,
) {
  final actual = payload.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException(
      '${kind.wire} config keys must be exactly ${expected.toList()..sort()}.',
    );
  }
}

bool _requireBool(
  Map<String, Object?> payload,
  String key,
  PortfolioStrategyKind kind,
) {
  final value = payload[key];
  if (value is! bool) {
    throw FormatException('${kind.wire}.$key must be a boolean.');
  }
  return value;
}
