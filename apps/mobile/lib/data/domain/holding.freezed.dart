// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'holding.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Holding {
  String get accountId => throw _privateConstructorUsedError;
  String get assetId => throw _privateConstructorUsedError;
  Decimal get quantity => throw _privateConstructorUsedError;
  Decimal get averageCost => throw _privateConstructorUsedError;
  Decimal get marketValue => throw _privateConstructorUsedError;
  Decimal get unrealizedPnl => throw _privateConstructorUsedError;
  String get currency => throw _privateConstructorUsedError;
  DateTime get asOf => throw _privateConstructorUsedError;

  /// Create a copy of Holding
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $HoldingCopyWith<Holding> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $HoldingCopyWith<$Res> {
  factory $HoldingCopyWith(Holding value, $Res Function(Holding) then) =
      _$HoldingCopyWithImpl<$Res, Holding>;
  @useResult
  $Res call({
    String accountId,
    String assetId,
    Decimal quantity,
    Decimal averageCost,
    Decimal marketValue,
    Decimal unrealizedPnl,
    String currency,
    DateTime asOf,
  });
}

/// @nodoc
class _$HoldingCopyWithImpl<$Res, $Val extends Holding>
    implements $HoldingCopyWith<$Res> {
  _$HoldingCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Holding
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? accountId = null,
    Object? assetId = null,
    Object? quantity = null,
    Object? averageCost = null,
    Object? marketValue = null,
    Object? unrealizedPnl = null,
    Object? currency = null,
    Object? asOf = null,
  }) {
    return _then(
      _value.copyWith(
            accountId: null == accountId
                ? _value.accountId
                : accountId // ignore: cast_nullable_to_non_nullable
                      as String,
            assetId: null == assetId
                ? _value.assetId
                : assetId // ignore: cast_nullable_to_non_nullable
                      as String,
            quantity: null == quantity
                ? _value.quantity
                : quantity // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            averageCost: null == averageCost
                ? _value.averageCost
                : averageCost // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            marketValue: null == marketValue
                ? _value.marketValue
                : marketValue // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            unrealizedPnl: null == unrealizedPnl
                ? _value.unrealizedPnl
                : unrealizedPnl // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            currency: null == currency
                ? _value.currency
                : currency // ignore: cast_nullable_to_non_nullable
                      as String,
            asOf: null == asOf
                ? _value.asOf
                : asOf // ignore: cast_nullable_to_non_nullable
                      as DateTime,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$HoldingImplCopyWith<$Res> implements $HoldingCopyWith<$Res> {
  factory _$$HoldingImplCopyWith(
    _$HoldingImpl value,
    $Res Function(_$HoldingImpl) then,
  ) = __$$HoldingImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String accountId,
    String assetId,
    Decimal quantity,
    Decimal averageCost,
    Decimal marketValue,
    Decimal unrealizedPnl,
    String currency,
    DateTime asOf,
  });
}

/// @nodoc
class __$$HoldingImplCopyWithImpl<$Res>
    extends _$HoldingCopyWithImpl<$Res, _$HoldingImpl>
    implements _$$HoldingImplCopyWith<$Res> {
  __$$HoldingImplCopyWithImpl(
    _$HoldingImpl _value,
    $Res Function(_$HoldingImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Holding
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? accountId = null,
    Object? assetId = null,
    Object? quantity = null,
    Object? averageCost = null,
    Object? marketValue = null,
    Object? unrealizedPnl = null,
    Object? currency = null,
    Object? asOf = null,
  }) {
    return _then(
      _$HoldingImpl(
        accountId: null == accountId
            ? _value.accountId
            : accountId // ignore: cast_nullable_to_non_nullable
                  as String,
        assetId: null == assetId
            ? _value.assetId
            : assetId // ignore: cast_nullable_to_non_nullable
                  as String,
        quantity: null == quantity
            ? _value.quantity
            : quantity // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        averageCost: null == averageCost
            ? _value.averageCost
            : averageCost // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        marketValue: null == marketValue
            ? _value.marketValue
            : marketValue // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        unrealizedPnl: null == unrealizedPnl
            ? _value.unrealizedPnl
            : unrealizedPnl // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        currency: null == currency
            ? _value.currency
            : currency // ignore: cast_nullable_to_non_nullable
                  as String,
        asOf: null == asOf
            ? _value.asOf
            : asOf // ignore: cast_nullable_to_non_nullable
                  as DateTime,
      ),
    );
  }
}

/// @nodoc

class _$HoldingImpl implements _Holding {
  const _$HoldingImpl({
    required this.accountId,
    required this.assetId,
    required this.quantity,
    required this.averageCost,
    required this.marketValue,
    required this.unrealizedPnl,
    required this.currency,
    required this.asOf,
  });

  @override
  final String accountId;
  @override
  final String assetId;
  @override
  final Decimal quantity;
  @override
  final Decimal averageCost;
  @override
  final Decimal marketValue;
  @override
  final Decimal unrealizedPnl;
  @override
  final String currency;
  @override
  final DateTime asOf;

  @override
  String toString() {
    return 'Holding(accountId: $accountId, assetId: $assetId, quantity: $quantity, averageCost: $averageCost, marketValue: $marketValue, unrealizedPnl: $unrealizedPnl, currency: $currency, asOf: $asOf)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$HoldingImpl &&
            (identical(other.accountId, accountId) ||
                other.accountId == accountId) &&
            (identical(other.assetId, assetId) || other.assetId == assetId) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity) &&
            (identical(other.averageCost, averageCost) ||
                other.averageCost == averageCost) &&
            (identical(other.marketValue, marketValue) ||
                other.marketValue == marketValue) &&
            (identical(other.unrealizedPnl, unrealizedPnl) ||
                other.unrealizedPnl == unrealizedPnl) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            (identical(other.asOf, asOf) || other.asOf == asOf));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    accountId,
    assetId,
    quantity,
    averageCost,
    marketValue,
    unrealizedPnl,
    currency,
    asOf,
  );

  /// Create a copy of Holding
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$HoldingImplCopyWith<_$HoldingImpl> get copyWith =>
      __$$HoldingImplCopyWithImpl<_$HoldingImpl>(this, _$identity);
}

abstract class _Holding implements Holding {
  const factory _Holding({
    required final String accountId,
    required final String assetId,
    required final Decimal quantity,
    required final Decimal averageCost,
    required final Decimal marketValue,
    required final Decimal unrealizedPnl,
    required final String currency,
    required final DateTime asOf,
  }) = _$HoldingImpl;

  @override
  String get accountId;
  @override
  String get assetId;
  @override
  Decimal get quantity;
  @override
  Decimal get averageCost;
  @override
  Decimal get marketValue;
  @override
  Decimal get unrealizedPnl;
  @override
  String get currency;
  @override
  DateTime get asOf;

  /// Create a copy of Holding
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$HoldingImplCopyWith<_$HoldingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
