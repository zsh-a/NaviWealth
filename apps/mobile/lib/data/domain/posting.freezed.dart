// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'posting.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Cost {

 Decimal get perUnit; String get currency; String? get lotId; DateTime? get acquiredOn;
/// Create a copy of Cost
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CostCopyWith<Cost> get copyWith => _$CostCopyWithImpl<Cost>(this as Cost, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Cost&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.lotId, lotId) || other.lotId == lotId)&&(identical(other.acquiredOn, acquiredOn) || other.acquiredOn == acquiredOn));
}


@override
int get hashCode => Object.hash(runtimeType,perUnit,currency,lotId,acquiredOn);

@override
String toString() {
  return 'Cost(perUnit: $perUnit, currency: $currency, lotId: $lotId, acquiredOn: $acquiredOn)';
}


}

/// @nodoc
abstract mixin class $CostCopyWith<$Res>  {
  factory $CostCopyWith(Cost value, $Res Function(Cost) _then) = _$CostCopyWithImpl;
@useResult
$Res call({
 Decimal perUnit, String currency, String? lotId, DateTime? acquiredOn
});




}
/// @nodoc
class _$CostCopyWithImpl<$Res>
    implements $CostCopyWith<$Res> {
  _$CostCopyWithImpl(this._self, this._then);

  final Cost _self;
  final $Res Function(Cost) _then;

/// Create a copy of Cost
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? perUnit = null,Object? currency = null,Object? lotId = freezed,Object? acquiredOn = freezed,}) {
  return _then(_self.copyWith(
perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,lotId: freezed == lotId ? _self.lotId : lotId // ignore: cast_nullable_to_non_nullable
as String?,acquiredOn: freezed == acquiredOn ? _self.acquiredOn : acquiredOn // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Cost].
extension CostPatterns on Cost {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Cost value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Cost() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Cost value)  $default,){
final _that = this;
switch (_that) {
case _Cost():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Cost value)?  $default,){
final _that = this;
switch (_that) {
case _Cost() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Decimal perUnit,  String currency,  String? lotId,  DateTime? acquiredOn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Cost() when $default != null:
return $default(_that.perUnit,_that.currency,_that.lotId,_that.acquiredOn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Decimal perUnit,  String currency,  String? lotId,  DateTime? acquiredOn)  $default,) {final _that = this;
switch (_that) {
case _Cost():
return $default(_that.perUnit,_that.currency,_that.lotId,_that.acquiredOn);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Decimal perUnit,  String currency,  String? lotId,  DateTime? acquiredOn)?  $default,) {final _that = this;
switch (_that) {
case _Cost() when $default != null:
return $default(_that.perUnit,_that.currency,_that.lotId,_that.acquiredOn);case _:
  return null;

}
}

}

/// @nodoc


class _Cost implements Cost {
  const _Cost({required this.perUnit, required this.currency, this.lotId, this.acquiredOn});
  

@override final  Decimal perUnit;
@override final  String currency;
@override final  String? lotId;
@override final  DateTime? acquiredOn;

/// Create a copy of Cost
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CostCopyWith<_Cost> get copyWith => __$CostCopyWithImpl<_Cost>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Cost&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.lotId, lotId) || other.lotId == lotId)&&(identical(other.acquiredOn, acquiredOn) || other.acquiredOn == acquiredOn));
}


@override
int get hashCode => Object.hash(runtimeType,perUnit,currency,lotId,acquiredOn);

@override
String toString() {
  return 'Cost(perUnit: $perUnit, currency: $currency, lotId: $lotId, acquiredOn: $acquiredOn)';
}


}

/// @nodoc
abstract mixin class _$CostCopyWith<$Res> implements $CostCopyWith<$Res> {
  factory _$CostCopyWith(_Cost value, $Res Function(_Cost) _then) = __$CostCopyWithImpl;
@override @useResult
$Res call({
 Decimal perUnit, String currency, String? lotId, DateTime? acquiredOn
});




}
/// @nodoc
class __$CostCopyWithImpl<$Res>
    implements _$CostCopyWith<$Res> {
  __$CostCopyWithImpl(this._self, this._then);

  final _Cost _self;
  final $Res Function(_Cost) _then;

/// Create a copy of Cost
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? perUnit = null,Object? currency = null,Object? lotId = freezed,Object? acquiredOn = freezed,}) {
  return _then(_Cost(
perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,lotId: freezed == lotId ? _self.lotId : lotId // ignore: cast_nullable_to_non_nullable
as String?,acquiredOn: freezed == acquiredOn ? _self.acquiredOn : acquiredOn // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$Price {

 Decimal get perUnit; String get currency;
/// Create a copy of Price
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PriceCopyWith<Price> get copyWith => _$PriceCopyWithImpl<Price>(this as Price, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Price&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.currency, currency) || other.currency == currency));
}


@override
int get hashCode => Object.hash(runtimeType,perUnit,currency);

@override
String toString() {
  return 'Price(perUnit: $perUnit, currency: $currency)';
}


}

/// @nodoc
abstract mixin class $PriceCopyWith<$Res>  {
  factory $PriceCopyWith(Price value, $Res Function(Price) _then) = _$PriceCopyWithImpl;
@useResult
$Res call({
 Decimal perUnit, String currency
});




}
/// @nodoc
class _$PriceCopyWithImpl<$Res>
    implements $PriceCopyWith<$Res> {
  _$PriceCopyWithImpl(this._self, this._then);

  final Price _self;
  final $Res Function(Price) _then;

/// Create a copy of Price
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? perUnit = null,Object? currency = null,}) {
  return _then(_self.copyWith(
perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Price].
extension PricePatterns on Price {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Price value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Price() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Price value)  $default,){
final _that = this;
switch (_that) {
case _Price():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Price value)?  $default,){
final _that = this;
switch (_that) {
case _Price() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Decimal perUnit,  String currency)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Price() when $default != null:
return $default(_that.perUnit,_that.currency);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Decimal perUnit,  String currency)  $default,) {final _that = this;
switch (_that) {
case _Price():
return $default(_that.perUnit,_that.currency);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Decimal perUnit,  String currency)?  $default,) {final _that = this;
switch (_that) {
case _Price() when $default != null:
return $default(_that.perUnit,_that.currency);case _:
  return null;

}
}

}

/// @nodoc


class _Price implements Price {
  const _Price({required this.perUnit, required this.currency});
  

@override final  Decimal perUnit;
@override final  String currency;

/// Create a copy of Price
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PriceCopyWith<_Price> get copyWith => __$PriceCopyWithImpl<_Price>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Price&&(identical(other.perUnit, perUnit) || other.perUnit == perUnit)&&(identical(other.currency, currency) || other.currency == currency));
}


@override
int get hashCode => Object.hash(runtimeType,perUnit,currency);

@override
String toString() {
  return 'Price(perUnit: $perUnit, currency: $currency)';
}


}

/// @nodoc
abstract mixin class _$PriceCopyWith<$Res> implements $PriceCopyWith<$Res> {
  factory _$PriceCopyWith(_Price value, $Res Function(_Price) _then) = __$PriceCopyWithImpl;
@override @useResult
$Res call({
 Decimal perUnit, String currency
});




}
/// @nodoc
class __$PriceCopyWithImpl<$Res>
    implements _$PriceCopyWith<$Res> {
  __$PriceCopyWithImpl(this._self, this._then);

  final _Price _self;
  final $Res Function(_Price) _then;

/// Create a copy of Price
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? perUnit = null,Object? currency = null,}) {
  return _then(_Price(
perUnit: null == perUnit ? _self.perUnit : perUnit // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$Posting {

 String get id; String get journalEntryId;/// Position within the JE (0-based). Determines render order in the
/// editor and the export. Stored explicitly so re-ordering is a
/// single-column LWW update rather than a JE-wide rewrite.
 int get position; String get accountId; Decimal get units; String get unit;/// Cost annotation — set when this leg opens or closes a specific
/// lot. See [Cost].
 Cost? get cost;/// Price annotation — set when this leg carries an explicit market
/// price (FX spot, sale price, etc.). See [Price].
 Price? get price; SyncMeta get sync;
/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PostingCopyWith<Posting> get copyWith => _$PostingCopyWithImpl<Posting>(this as Posting, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Posting&&(identical(other.id, id) || other.id == id)&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.position, position) || other.position == position)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.units, units) || other.units == units)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.cost, cost) || other.cost == cost)&&(identical(other.price, price) || other.price == price)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,journalEntryId,position,accountId,units,unit,cost,price,sync);

@override
String toString() {
  return 'Posting(id: $id, journalEntryId: $journalEntryId, position: $position, accountId: $accountId, units: $units, unit: $unit, cost: $cost, price: $price, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $PostingCopyWith<$Res>  {
  factory $PostingCopyWith(Posting value, $Res Function(Posting) _then) = _$PostingCopyWithImpl;
@useResult
$Res call({
 String id, String journalEntryId, int position, String accountId, Decimal units, String unit, Cost? cost, Price? price, SyncMeta sync
});


$CostCopyWith<$Res>? get cost;$PriceCopyWith<$Res>? get price;$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$PostingCopyWithImpl<$Res>
    implements $PostingCopyWith<$Res> {
  _$PostingCopyWithImpl(this._self, this._then);

  final Posting _self;
  final $Res Function(Posting) _then;

/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? journalEntryId = null,Object? position = null,Object? accountId = null,Object? units = null,Object? unit = null,Object? cost = freezed,Object? price = freezed,Object? sync = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as Decimal,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as Cost?,price: freezed == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Price?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CostCopyWith<$Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $CostCopyWith<$Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PriceCopyWith<$Res>? get price {
    if (_self.price == null) {
    return null;
  }

  return $PriceCopyWith<$Res>(_self.price!, (value) {
    return _then(_self.copyWith(price: value));
  });
}/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Posting].
extension PostingPatterns on Posting {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Posting value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Posting() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Posting value)  $default,){
final _that = this;
switch (_that) {
case _Posting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Posting value)?  $default,){
final _that = this;
switch (_that) {
case _Posting() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String journalEntryId,  int position,  String accountId,  Decimal units,  String unit,  Cost? cost,  Price? price,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Posting() when $default != null:
return $default(_that.id,_that.journalEntryId,_that.position,_that.accountId,_that.units,_that.unit,_that.cost,_that.price,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String journalEntryId,  int position,  String accountId,  Decimal units,  String unit,  Cost? cost,  Price? price,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Posting():
return $default(_that.id,_that.journalEntryId,_that.position,_that.accountId,_that.units,_that.unit,_that.cost,_that.price,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String journalEntryId,  int position,  String accountId,  Decimal units,  String unit,  Cost? cost,  Price? price,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Posting() when $default != null:
return $default(_that.id,_that.journalEntryId,_that.position,_that.accountId,_that.units,_that.unit,_that.cost,_that.price,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Posting implements Posting {
  const _Posting({required this.id, required this.journalEntryId, required this.position, required this.accountId, required this.units, required this.unit, this.cost, this.price, required this.sync});
  

@override final  String id;
@override final  String journalEntryId;
/// Position within the JE (0-based). Determines render order in the
/// editor and the export. Stored explicitly so re-ordering is a
/// single-column LWW update rather than a JE-wide rewrite.
@override final  int position;
@override final  String accountId;
@override final  Decimal units;
@override final  String unit;
/// Cost annotation — set when this leg opens or closes a specific
/// lot. See [Cost].
@override final  Cost? cost;
/// Price annotation — set when this leg carries an explicit market
/// price (FX spot, sale price, etc.). See [Price].
@override final  Price? price;
@override final  SyncMeta sync;

/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PostingCopyWith<_Posting> get copyWith => __$PostingCopyWithImpl<_Posting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Posting&&(identical(other.id, id) || other.id == id)&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.position, position) || other.position == position)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.units, units) || other.units == units)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.cost, cost) || other.cost == cost)&&(identical(other.price, price) || other.price == price)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,journalEntryId,position,accountId,units,unit,cost,price,sync);

@override
String toString() {
  return 'Posting(id: $id, journalEntryId: $journalEntryId, position: $position, accountId: $accountId, units: $units, unit: $unit, cost: $cost, price: $price, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$PostingCopyWith<$Res> implements $PostingCopyWith<$Res> {
  factory _$PostingCopyWith(_Posting value, $Res Function(_Posting) _then) = __$PostingCopyWithImpl;
@override @useResult
$Res call({
 String id, String journalEntryId, int position, String accountId, Decimal units, String unit, Cost? cost, Price? price, SyncMeta sync
});


@override $CostCopyWith<$Res>? get cost;@override $PriceCopyWith<$Res>? get price;@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$PostingCopyWithImpl<$Res>
    implements _$PostingCopyWith<$Res> {
  __$PostingCopyWithImpl(this._self, this._then);

  final _Posting _self;
  final $Res Function(_Posting) _then;

/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? journalEntryId = null,Object? position = null,Object? accountId = null,Object? units = null,Object? unit = null,Object? cost = freezed,Object? price = freezed,Object? sync = null,}) {
  return _then(_Posting(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as Decimal,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as Cost?,price: freezed == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Price?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CostCopyWith<$Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $CostCopyWith<$Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}/// Create a copy of Posting
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PriceCopyWith<$Res>? get price {
    if (_self.price == null) {
    return null;
  }

  return $PriceCopyWith<$Res>(_self.price!, (value) {
    return _then(_self.copyWith(price: value));
  });
}/// Create a copy of Posting
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
