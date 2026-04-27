// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fx_rate.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$FxRate {
  String get id => throw _privateConstructorUsedError;
  String get baseCurrency => throw _privateConstructorUsedError;
  String get quoteCurrency => throw _privateConstructorUsedError;
  Decimal get rate => throw _privateConstructorUsedError;
  DateTime get asOf => throw _privateConstructorUsedError;
  String? get source => throw _privateConstructorUsedError;

  /// Create a copy of FxRate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FxRateCopyWith<FxRate> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FxRateCopyWith<$Res> {
  factory $FxRateCopyWith(FxRate value, $Res Function(FxRate) then) =
      _$FxRateCopyWithImpl<$Res, FxRate>;
  @useResult
  $Res call({
    String id,
    String baseCurrency,
    String quoteCurrency,
    Decimal rate,
    DateTime asOf,
    String? source,
  });
}

/// @nodoc
class _$FxRateCopyWithImpl<$Res, $Val extends FxRate>
    implements $FxRateCopyWith<$Res> {
  _$FxRateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FxRate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? baseCurrency = null,
    Object? quoteCurrency = null,
    Object? rate = null,
    Object? asOf = null,
    Object? source = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            baseCurrency: null == baseCurrency
                ? _value.baseCurrency
                : baseCurrency // ignore: cast_nullable_to_non_nullable
                      as String,
            quoteCurrency: null == quoteCurrency
                ? _value.quoteCurrency
                : quoteCurrency // ignore: cast_nullable_to_non_nullable
                      as String,
            rate: null == rate
                ? _value.rate
                : rate // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            asOf: null == asOf
                ? _value.asOf
                : asOf // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            source: freezed == source
                ? _value.source
                : source // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FxRateImplCopyWith<$Res> implements $FxRateCopyWith<$Res> {
  factory _$$FxRateImplCopyWith(
    _$FxRateImpl value,
    $Res Function(_$FxRateImpl) then,
  ) = __$$FxRateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String baseCurrency,
    String quoteCurrency,
    Decimal rate,
    DateTime asOf,
    String? source,
  });
}

/// @nodoc
class __$$FxRateImplCopyWithImpl<$Res>
    extends _$FxRateCopyWithImpl<$Res, _$FxRateImpl>
    implements _$$FxRateImplCopyWith<$Res> {
  __$$FxRateImplCopyWithImpl(
    _$FxRateImpl _value,
    $Res Function(_$FxRateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FxRate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? baseCurrency = null,
    Object? quoteCurrency = null,
    Object? rate = null,
    Object? asOf = null,
    Object? source = freezed,
  }) {
    return _then(
      _$FxRateImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        baseCurrency: null == baseCurrency
            ? _value.baseCurrency
            : baseCurrency // ignore: cast_nullable_to_non_nullable
                  as String,
        quoteCurrency: null == quoteCurrency
            ? _value.quoteCurrency
            : quoteCurrency // ignore: cast_nullable_to_non_nullable
                  as String,
        rate: null == rate
            ? _value.rate
            : rate // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        asOf: null == asOf
            ? _value.asOf
            : asOf // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        source: freezed == source
            ? _value.source
            : source // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$FxRateImpl implements _FxRate {
  const _$FxRateImpl({
    required this.id,
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.rate,
    required this.asOf,
    this.source,
  });

  @override
  final String id;
  @override
  final String baseCurrency;
  @override
  final String quoteCurrency;
  @override
  final Decimal rate;
  @override
  final DateTime asOf;
  @override
  final String? source;

  @override
  String toString() {
    return 'FxRate(id: $id, baseCurrency: $baseCurrency, quoteCurrency: $quoteCurrency, rate: $rate, asOf: $asOf, source: $source)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FxRateImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.baseCurrency, baseCurrency) ||
                other.baseCurrency == baseCurrency) &&
            (identical(other.quoteCurrency, quoteCurrency) ||
                other.quoteCurrency == quoteCurrency) &&
            (identical(other.rate, rate) || other.rate == rate) &&
            (identical(other.asOf, asOf) || other.asOf == asOf) &&
            (identical(other.source, source) || other.source == source));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    baseCurrency,
    quoteCurrency,
    rate,
    asOf,
    source,
  );

  /// Create a copy of FxRate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FxRateImplCopyWith<_$FxRateImpl> get copyWith =>
      __$$FxRateImplCopyWithImpl<_$FxRateImpl>(this, _$identity);
}

abstract class _FxRate implements FxRate {
  const factory _FxRate({
    required final String id,
    required final String baseCurrency,
    required final String quoteCurrency,
    required final Decimal rate,
    required final DateTime asOf,
    final String? source,
  }) = _$FxRateImpl;

  @override
  String get id;
  @override
  String get baseCurrency;
  @override
  String get quoteCurrency;
  @override
  Decimal get rate;
  @override
  DateTime get asOf;
  @override
  String? get source;

  /// Create a copy of FxRate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FxRateImplCopyWith<_$FxRateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
