// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'price_observation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PriceObservation {

 String get id; String get unit; String get quoteCurrency; DateTime get observedOn; Decimal get perUnit;/// Where this observation came from. Free-form by design — the
/// expected values are `'manual'`, `'yahoo'`, `'coingecko'` etc., but
/// we don't constrain the column so a future provider can be added
/// without a schema migration.
 String get source; SyncMeta get sync;
/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PriceObservationCopyWith<PriceObservation> get copyWith => _$PriceObservationCopyWithImpl<PriceObservation>(this as PriceObservation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PriceObservation&&(identical(other.id, id) || other.id == id)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.quoteCurrency, quoteCurrency) || other.quoteCurrency == quoteCurrency)&&(identical(other.observedOn, observedOn) || other.observedOn == observedOn)&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.source, source) || other.source == source)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,unit,quoteCurrency,observedOn,perUnit,source,sync);

@override
String toString() {
  return 'PriceObservation(id: $id, unit: $unit, quoteCurrency: $quoteCurrency, observedOn: $observedOn, perUnit: $perUnit, source: $source, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $PriceObservationCopyWith<$Res>  {
  factory $PriceObservationCopyWith(PriceObservation value, $Res Function(PriceObservation) _then) = _$PriceObservationCopyWithImpl;
@useResult
$Res call({
 String id, String unit, String quoteCurrency, DateTime observedOn, Decimal perUnit, String source, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$PriceObservationCopyWithImpl<$Res>
    implements $PriceObservationCopyWith<$Res> {
  _$PriceObservationCopyWithImpl(this._self, this._then);

  final PriceObservation _self;
  final $Res Function(PriceObservation) _then;

/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? unit = null,Object? quoteCurrency = null,Object? observedOn = null,Object? perUnit = null,Object? source = null,Object? sync = null,}) {
  return _then(PriceObservation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,quoteCurrency: null == quoteCurrency ? _self.quoteCurrency : quoteCurrency // ignore: cast_nullable_to_non_nullable
as String,observedOn: null == observedOn ? _self.observedOn : observedOn // ignore: cast_nullable_to_non_nullable
as DateTime,perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [PriceObservation].
extension PriceObservationPatterns on PriceObservation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PriceObservation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PriceObservation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PriceObservation value)  $default,){
final _that = this;
switch (_that) {
case _PriceObservation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PriceObservation value)?  $default,){
final _that = this;
switch (_that) {
case _PriceObservation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String unit,  String quoteCurrency,  DateTime observedOn,  Decimal perUnit,  String source,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PriceObservation() when $default != null:
return $default(_that.id,_that.unit,_that.quoteCurrency,_that.observedOn,_that.perUnit,_that.source,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String unit,  String quoteCurrency,  DateTime observedOn,  Decimal perUnit,  String source,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _PriceObservation():
return $default(_that.id,_that.unit,_that.quoteCurrency,_that.observedOn,_that.perUnit,_that.source,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String unit,  String quoteCurrency,  DateTime observedOn,  Decimal perUnit,  String source,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _PriceObservation() when $default != null:
return $default(_that.id,_that.unit,_that.quoteCurrency,_that.observedOn,_that.perUnit,_that.source,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _PriceObservation implements PriceObservation {
  const _PriceObservation({required this.id, required this.unit, required this.quoteCurrency, required this.observedOn, required this.perUnit, required this.source, required this.sync});
  

@override final  String id;
@override final  String unit;
@override final  String quoteCurrency;
@override final  DateTime observedOn;
@override final  Decimal perUnit;
/// Where this observation came from. Free-form by design — the
/// expected values are `'manual'`, `'yahoo'`, `'coingecko'` etc., but
/// we don't constrain the column so a future provider can be added
/// without a schema migration.
@override final  String source;
@override final  SyncMeta sync;

/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PriceObservationCopyWith<_PriceObservation> get copyWith => __$PriceObservationCopyWithImpl<_PriceObservation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PriceObservation&&(identical(other.id, id) || other.id == id)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.quoteCurrency, quoteCurrency) || other.quoteCurrency == quoteCurrency)&&(identical(other.observedOn, observedOn) || other.observedOn == observedOn)&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.source, source) || other.source == source)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,unit,quoteCurrency,observedOn,perUnit,source,sync);

@override
String toString() {
  return 'PriceObservation(id: $id, unit: $unit, quoteCurrency: $quoteCurrency, observedOn: $observedOn, perUnit: $perUnit, source: $source, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$PriceObservationCopyWith<$Res> implements $PriceObservationCopyWith<$Res> {
  factory _$PriceObservationCopyWith(_PriceObservation value, $Res Function(_PriceObservation) _then) = __$PriceObservationCopyWithImpl;
@override @useResult
$Res call({
 String id, String unit, String quoteCurrency, DateTime observedOn, Decimal perUnit, String source, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$PriceObservationCopyWithImpl<$Res>
    implements _$PriceObservationCopyWith<$Res> {
  __$PriceObservationCopyWithImpl(this._self, this._then);

  final _PriceObservation _self;
  final $Res Function(_PriceObservation) _then;

/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? unit = null,Object? quoteCurrency = null,Object? observedOn = null,Object? perUnit = null,Object? source = null,Object? sync = null,}) {
  return _then(_PriceObservation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,quoteCurrency: null == quoteCurrency ? _self.quoteCurrency : quoteCurrency // ignore: cast_nullable_to_non_nullable
as String,observedOn: null == observedOn ? _self.observedOn : observedOn // ignore: cast_nullable_to_non_nullable
as DateTime,perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of PriceObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}

// dart format on
