// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'holding.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Holding {

 String get accountId; String get assetId; Decimal get quantity; Decimal get averageCost; Decimal get marketValue; Decimal get unrealizedPnl; String get currency; DateTime get asOf;
/// Create a copy of Holding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HoldingCopyWith<Holding> get copyWith => _$HoldingCopyWithImpl<Holding>(this as Holding, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Holding&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.averageCost, averageCost) || other.averageCost == averageCost)&&(identical(other.marketValue, marketValue) || other.marketValue == marketValue)&&(identical(other.unrealizedPnl, unrealizedPnl) || other.unrealizedPnl == unrealizedPnl)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.asOf, asOf) || other.asOf == asOf));
}


@override
int get hashCode => Object.hash(runtimeType,accountId,assetId,quantity,averageCost,marketValue,unrealizedPnl,currency,asOf);

@override
String toString() {
  return 'Holding(accountId: $accountId, assetId: $assetId, quantity: $quantity, averageCost: $averageCost, marketValue: $marketValue, unrealizedPnl: $unrealizedPnl, currency: $currency, asOf: $asOf)';
}


}

/// @nodoc
abstract mixin class $HoldingCopyWith<$Res>  {
  factory $HoldingCopyWith(Holding value, $Res Function(Holding) _then) = _$HoldingCopyWithImpl;
@useResult
$Res call({
 String accountId, String assetId, Decimal quantity, Decimal averageCost, Decimal marketValue, Decimal unrealizedPnl, String currency, DateTime asOf
});




}
/// @nodoc
class _$HoldingCopyWithImpl<$Res>
    implements $HoldingCopyWith<$Res> {
  _$HoldingCopyWithImpl(this._self, this._then);

  final Holding _self;
  final $Res Function(Holding) _then;

/// Create a copy of Holding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? assetId = null,Object? quantity = null,Object? averageCost = null,Object? marketValue = null,Object? unrealizedPnl = null,Object? currency = null,Object? asOf = null,}) {
  return _then(_self.copyWith(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,assetId: null == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Decimal,averageCost: null == averageCost ? _self.averageCost : averageCost // ignore: cast_nullable_to_non_nullable
as Decimal,marketValue: null == marketValue ? _self.marketValue : marketValue // ignore: cast_nullable_to_non_nullable
as Decimal,unrealizedPnl: null == unrealizedPnl ? _self.unrealizedPnl : unrealizedPnl // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,asOf: null == asOf ? _self.asOf : asOf // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Holding].
extension HoldingPatterns on Holding {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Holding value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Holding() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Holding value)  $default,){
final _that = this;
switch (_that) {
case _Holding():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Holding value)?  $default,){
final _that = this;
switch (_that) {
case _Holding() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String assetId,  Decimal quantity,  Decimal averageCost,  Decimal marketValue,  Decimal unrealizedPnl,  String currency,  DateTime asOf)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Holding() when $default != null:
return $default(_that.accountId,_that.assetId,_that.quantity,_that.averageCost,_that.marketValue,_that.unrealizedPnl,_that.currency,_that.asOf);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String assetId,  Decimal quantity,  Decimal averageCost,  Decimal marketValue,  Decimal unrealizedPnl,  String currency,  DateTime asOf)  $default,) {final _that = this;
switch (_that) {
case _Holding():
return $default(_that.accountId,_that.assetId,_that.quantity,_that.averageCost,_that.marketValue,_that.unrealizedPnl,_that.currency,_that.asOf);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String assetId,  Decimal quantity,  Decimal averageCost,  Decimal marketValue,  Decimal unrealizedPnl,  String currency,  DateTime asOf)?  $default,) {final _that = this;
switch (_that) {
case _Holding() when $default != null:
return $default(_that.accountId,_that.assetId,_that.quantity,_that.averageCost,_that.marketValue,_that.unrealizedPnl,_that.currency,_that.asOf);case _:
  return null;

}
}

}

/// @nodoc


class _Holding implements Holding {
  const _Holding({required this.accountId, required this.assetId, required this.quantity, required this.averageCost, required this.marketValue, required this.unrealizedPnl, required this.currency, required this.asOf});
  

@override final  String accountId;
@override final  String assetId;
@override final  Decimal quantity;
@override final  Decimal averageCost;
@override final  Decimal marketValue;
@override final  Decimal unrealizedPnl;
@override final  String currency;
@override final  DateTime asOf;

/// Create a copy of Holding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HoldingCopyWith<_Holding> get copyWith => __$HoldingCopyWithImpl<_Holding>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Holding&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.averageCost, averageCost) || other.averageCost == averageCost)&&(identical(other.marketValue, marketValue) || other.marketValue == marketValue)&&(identical(other.unrealizedPnl, unrealizedPnl) || other.unrealizedPnl == unrealizedPnl)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.asOf, asOf) || other.asOf == asOf));
}


@override
int get hashCode => Object.hash(runtimeType,accountId,assetId,quantity,averageCost,marketValue,unrealizedPnl,currency,asOf);

@override
String toString() {
  return 'Holding(accountId: $accountId, assetId: $assetId, quantity: $quantity, averageCost: $averageCost, marketValue: $marketValue, unrealizedPnl: $unrealizedPnl, currency: $currency, asOf: $asOf)';
}


}

/// @nodoc
abstract mixin class _$HoldingCopyWith<$Res> implements $HoldingCopyWith<$Res> {
  factory _$HoldingCopyWith(_Holding value, $Res Function(_Holding) _then) = __$HoldingCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String assetId, Decimal quantity, Decimal averageCost, Decimal marketValue, Decimal unrealizedPnl, String currency, DateTime asOf
});




}
/// @nodoc
class __$HoldingCopyWithImpl<$Res>
    implements _$HoldingCopyWith<$Res> {
  __$HoldingCopyWithImpl(this._self, this._then);

  final _Holding _self;
  final $Res Function(_Holding) _then;

/// Create a copy of Holding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? assetId = null,Object? quantity = null,Object? averageCost = null,Object? marketValue = null,Object? unrealizedPnl = null,Object? currency = null,Object? asOf = null,}) {
  return _then(_Holding(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,assetId: null == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Decimal,averageCost: null == averageCost ? _self.averageCost : averageCost // ignore: cast_nullable_to_non_nullable
as Decimal,marketValue: null == marketValue ? _self.marketValue : marketValue // ignore: cast_nullable_to_non_nullable
as Decimal,unrealizedPnl: null == unrealizedPnl ? _self.unrealizedPnl : unrealizedPnl // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,asOf: null == asOf ? _self.asOf : asOf // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
