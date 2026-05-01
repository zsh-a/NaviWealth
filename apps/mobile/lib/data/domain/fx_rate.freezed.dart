// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fx_rate.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FxRate {

 String get id; String get baseCurrency; String get quoteCurrency; Decimal get rate; DateTime get asOf; String? get source;
/// Create a copy of FxRate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FxRateCopyWith<FxRate> get copyWith => _$FxRateCopyWithImpl<FxRate>(this as FxRate, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FxRate&&(identical(other.id, id) || other.id == id)&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.quoteCurrency, quoteCurrency) || other.quoteCurrency == quoteCurrency)&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.asOf, asOf) || other.asOf == asOf)&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,id,baseCurrency,quoteCurrency,rate,asOf,source);

@override
String toString() {
  return 'FxRate(id: $id, baseCurrency: $baseCurrency, quoteCurrency: $quoteCurrency, rate: $rate, asOf: $asOf, source: $source)';
}


}

/// @nodoc
abstract mixin class $FxRateCopyWith<$Res>  {
  factory $FxRateCopyWith(FxRate value, $Res Function(FxRate) _then) = _$FxRateCopyWithImpl;
@useResult
$Res call({
 String id, String baseCurrency, String quoteCurrency, Decimal rate, DateTime asOf, String? source
});




}
/// @nodoc
class _$FxRateCopyWithImpl<$Res>
    implements $FxRateCopyWith<$Res> {
  _$FxRateCopyWithImpl(this._self, this._then);

  final FxRate _self;
  final $Res Function(FxRate) _then;

/// Create a copy of FxRate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? baseCurrency = null,Object? quoteCurrency = null,Object? rate = null,Object? asOf = null,Object? source = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,quoteCurrency: null == quoteCurrency ? _self.quoteCurrency : quoteCurrency // ignore: cast_nullable_to_non_nullable
as String,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as Decimal,asOf: null == asOf ? _self.asOf : asOf // ignore: cast_nullable_to_non_nullable
as DateTime,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FxRate].
extension FxRatePatterns on FxRate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FxRate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FxRate() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FxRate value)  $default,){
final _that = this;
switch (_that) {
case _FxRate():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FxRate value)?  $default,){
final _that = this;
switch (_that) {
case _FxRate() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String baseCurrency,  String quoteCurrency,  Decimal rate,  DateTime asOf,  String? source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FxRate() when $default != null:
return $default(_that.id,_that.baseCurrency,_that.quoteCurrency,_that.rate,_that.asOf,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String baseCurrency,  String quoteCurrency,  Decimal rate,  DateTime asOf,  String? source)  $default,) {final _that = this;
switch (_that) {
case _FxRate():
return $default(_that.id,_that.baseCurrency,_that.quoteCurrency,_that.rate,_that.asOf,_that.source);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String baseCurrency,  String quoteCurrency,  Decimal rate,  DateTime asOf,  String? source)?  $default,) {final _that = this;
switch (_that) {
case _FxRate() when $default != null:
return $default(_that.id,_that.baseCurrency,_that.quoteCurrency,_that.rate,_that.asOf,_that.source);case _:
  return null;

}
}

}

/// @nodoc


class _FxRate implements FxRate {
  const _FxRate({required this.id, required this.baseCurrency, required this.quoteCurrency, required this.rate, required this.asOf, this.source});
  

@override final  String id;
@override final  String baseCurrency;
@override final  String quoteCurrency;
@override final  Decimal rate;
@override final  DateTime asOf;
@override final  String? source;

/// Create a copy of FxRate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FxRateCopyWith<_FxRate> get copyWith => __$FxRateCopyWithImpl<_FxRate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FxRate&&(identical(other.id, id) || other.id == id)&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.quoteCurrency, quoteCurrency) || other.quoteCurrency == quoteCurrency)&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.asOf, asOf) || other.asOf == asOf)&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,id,baseCurrency,quoteCurrency,rate,asOf,source);

@override
String toString() {
  return 'FxRate(id: $id, baseCurrency: $baseCurrency, quoteCurrency: $quoteCurrency, rate: $rate, asOf: $asOf, source: $source)';
}


}

/// @nodoc
abstract mixin class _$FxRateCopyWith<$Res> implements $FxRateCopyWith<$Res> {
  factory _$FxRateCopyWith(_FxRate value, $Res Function(_FxRate) _then) = __$FxRateCopyWithImpl;
@override @useResult
$Res call({
 String id, String baseCurrency, String quoteCurrency, Decimal rate, DateTime asOf, String? source
});




}
/// @nodoc
class __$FxRateCopyWithImpl<$Res>
    implements _$FxRateCopyWith<$Res> {
  __$FxRateCopyWithImpl(this._self, this._then);

  final _FxRate _self;
  final $Res Function(_FxRate) _then;

/// Create a copy of FxRate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? baseCurrency = null,Object? quoteCurrency = null,Object? rate = null,Object? asOf = null,Object? source = freezed,}) {
  return _then(_FxRate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,quoteCurrency: null == quoteCurrency ? _self.quoteCurrency : quoteCurrency // ignore: cast_nullable_to_non_nullable
as String,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as Decimal,asOf: null == asOf ? _self.asOf : asOf // ignore: cast_nullable_to_non_nullable
as DateTime,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
