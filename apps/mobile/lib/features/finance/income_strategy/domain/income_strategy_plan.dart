import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'income_strategy.dart';

const Object _unsetIncomePlanField = Object();

class IncomeStrategySettingKey {
  const IncomeStrategySettingKey(this.wire)
    : assert(wire != '', 'Setting wire id must not be empty.');

  final String wire;

  @override
  bool operator ==(Object other) =>
      other is IncomeStrategySettingKey && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

sealed class IncomeStrategySettingValue {
  const IncomeStrategySettingValue();

  Object toJson();

  static IncomeStrategySettingValue? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    final value = json['value'];
    if (type == 'bool' && value is bool) {
      return IncomeStrategyBoolSetting(value);
    }
    if (type == 'decimal' && value is String) {
      final parsed = Decimal.tryParse(value);
      return parsed == null ? null : IncomeStrategyDecimalSetting(parsed);
    }
    if (type == 'text' && value is String) {
      return IncomeStrategyTextSetting(value);
    }
    return null;
  }
}

class IncomeStrategyBoolSetting extends IncomeStrategySettingValue {
  const IncomeStrategyBoolSetting(this.value);

  final bool value;

  @override
  Object toJson() => <String, Object?>{'type': 'bool', 'value': value};
}

class IncomeStrategyDecimalSetting extends IncomeStrategySettingValue {
  const IncomeStrategyDecimalSetting(this.value);

  final Decimal value;

  @override
  Object toJson() => <String, Object?>{
    'type': 'decimal',
    'value': value.toString(),
  };
}

class IncomeStrategyTextSetting extends IncomeStrategySettingValue {
  const IncomeStrategyTextSetting(this.value);

  final String value;

  @override
  Object toJson() => <String, Object?>{'type': 'text', 'value': value};
}

/// Module-owned intent settings. The core plan only understands whether a
/// sleeve is enabled; each module owns the meaning and validation of settings.
class IncomeStrategySleeveIntent {
  const IncomeStrategySleeveIntent({
    required this.kind,
    required this.enabled,
    this.settings =
        const <IncomeStrategySettingKey, IncomeStrategySettingValue>{},
  });

  final IncomeStrategySleeveKind kind;
  final bool enabled;
  final Map<IncomeStrategySettingKey, IncomeStrategySettingValue> settings;

  bool boolValue(IncomeStrategySettingKey key, {required bool fallback}) {
    final value = settings[key];
    return value is IncomeStrategyBoolSetting ? value.value : fallback;
  }

  Decimal? decimalValue(IncomeStrategySettingKey key) {
    final value = settings[key];
    return value is IncomeStrategyDecimalSetting ? value.value : null;
  }

  String? textValue(IncomeStrategySettingKey key) {
    final value = settings[key];
    return value is IncomeStrategyTextSetting ? value.value : null;
  }
}

abstract final class DividendIncomeStrategySettings {
  static const preservePosition = IncomeStrategySettingKey('preserve_position');
}

abstract final class WheelIncomeStrategySettings {
  static const allowSharesCalledAway = IncomeStrategySettingKey(
    'allow_shares_called_away',
  );
  static const maxAssignmentValue = IncomeStrategySettingKey(
    'max_assignment_value',
  );
  static const allowPut = IncomeStrategySettingKey('allow_put');
  static const allowCall = IncomeStrategySettingKey('allow_call');
  static const maxBuyPrice = IncomeStrategySettingKey('max_buy_price');
  static const minSellPrice = IncomeStrategySettingKey('min_sell_price');
}

abstract final class LeapsIncomeStrategySettings {
  static const maxCost = IncomeStrategySettingKey('max_cost');
}

/// User intent and guardrails for composing strategy modules on one asset.
///
/// Live positions, prices and derived metrics stay in their owning FinanceOS
/// source models. Module-specific settings live inside [sleeveIntents], so a
/// new module never adds columns or fields to this shared plan.
class IncomeStrategyPlan {
  const IncomeStrategyPlan({
    required this.id,
    required this.assetId,
    required this.symbol,
    required this.market,
    required this.currency,
    required this.sleeveIntents,
    required this.capitalBudget,
    required this.annualIncomeTarget,
    required this.maxPositionWeight,
    required this.notes,
    required this.sync,
    this.groupId,
    this.groupLabel,
  });

  /// Stable sync row id. It is not the asset id; owner/asset uniqueness is a
  /// repository invariant so two local users can plan the same security.
  final String id;
  final String assetId;
  final String symbol;
  final String market;
  final String currency;
  final Map<IncomeStrategySleeveKind, IncomeStrategySleeveIntent> sleeveIntents;
  final Decimal? capitalBudget;
  final Decimal? annualIncomeTarget;
  final Decimal? maxPositionWeight;
  final String? notes;

  /// Optional strategy group. Plans sharing a non-empty [groupId] are
  /// coordinated as one group (cross-underlying wheel/LEAPS pairing);
  /// null means the asset forms its own implicit singleton group.
  final String? groupId;
  final String? groupLabel;
  final SyncMeta sync;

  Set<IncomeStrategySleeveKind> get enabledSleeves => Set.unmodifiable(
    sleeveIntents.values
        .where((intent) => intent.enabled)
        .map((intent) => intent.kind),
  );

  Money? get capitalBudgetMoney =>
      capitalBudget == null ? null : Money(capitalBudget!, currency);

  Money? get annualIncomeTargetMoney =>
      annualIncomeTarget == null ? null : Money(annualIncomeTarget!, currency);

  IncomeStrategySleeveIntent? intent(IncomeStrategySleeveKind kind) =>
      sleeveIntents[kind];

  IncomeStrategyPlan copyWith({
    Map<IncomeStrategySleeveKind, IncomeStrategySleeveIntent>? sleeveIntents,
    Object? capitalBudget = _unsetIncomePlanField,
    Object? annualIncomeTarget = _unsetIncomePlanField,
    Object? maxPositionWeight = _unsetIncomePlanField,
    Object? notes = _unsetIncomePlanField,
    Object? groupId = _unsetIncomePlanField,
    Object? groupLabel = _unsetIncomePlanField,
    SyncMeta? sync,
  }) => IncomeStrategyPlan(
    id: id,
    assetId: assetId,
    symbol: symbol,
    market: market,
    currency: currency,
    sleeveIntents: sleeveIntents ?? this.sleeveIntents,
    capitalBudget: identical(capitalBudget, _unsetIncomePlanField)
        ? this.capitalBudget
        : capitalBudget as Decimal?,
    annualIncomeTarget: identical(annualIncomeTarget, _unsetIncomePlanField)
        ? this.annualIncomeTarget
        : annualIncomeTarget as Decimal?,
    maxPositionWeight: identical(maxPositionWeight, _unsetIncomePlanField)
        ? this.maxPositionWeight
        : maxPositionWeight as Decimal?,
    notes: identical(notes, _unsetIncomePlanField)
        ? this.notes
        : notes as String?,
    groupId: identical(groupId, _unsetIncomePlanField)
        ? this.groupId
        : groupId as String?,
    groupLabel: identical(groupLabel, _unsetIncomePlanField)
        ? this.groupLabel
        : groupLabel as String?,
    sync: sync ?? this.sync,
  );
}
