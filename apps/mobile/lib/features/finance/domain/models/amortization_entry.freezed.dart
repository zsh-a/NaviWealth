// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'amortization_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AmortizationEntry {

 String get id; String get liabilityId; int get periodIndex; DateTime get dueDate; Decimal get principalPayment; Decimal get interestPayment; Decimal get remainingBalance; DateTime? get paidAt; SyncMeta get sync;
/// Create a copy of AmortizationEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AmortizationEntryCopyWith<AmortizationEntry> get copyWith => _$AmortizationEntryCopyWithImpl<AmortizationEntry>(this as AmortizationEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AmortizationEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AmortizationEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.liabilityId, _this.liabilityId) || other.liabilityId == _this.liabilityId)&&(identical(other.periodIndex, _this.periodIndex) || other.periodIndex == _this.periodIndex)&&(identical(other.dueDate, _this.dueDate) || other.dueDate == _this.dueDate)&&(identical(other.principalPayment, _this.principalPayment) || other.principalPayment == _this.principalPayment)&&(identical(other.interestPayment, _this.interestPayment) || other.interestPayment == _this.interestPayment)&&(identical(other.remainingBalance, _this.remainingBalance) || other.remainingBalance == _this.remainingBalance)&&(identical(other.paidAt, _this.paidAt) || other.paidAt == _this.paidAt)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as AmortizationEntry;
  return Object.hash(runtimeType,_this.id,_this.liabilityId,_this.periodIndex,_this.dueDate,_this.principalPayment,_this.interestPayment,_this.remainingBalance,_this.paidAt,_this.sync);
}

@override
String toString() {
  final _this = this as AmortizationEntry;
  return 'AmortizationEntry(id: ${_this.id}, liabilityId: ${_this.liabilityId}, periodIndex: ${_this.periodIndex}, dueDate: ${_this.dueDate}, principalPayment: ${_this.principalPayment}, interestPayment: ${_this.interestPayment}, remainingBalance: ${_this.remainingBalance}, paidAt: ${_this.paidAt}, sync: ${_this.sync})';
}


}

/// @nodoc
abstract mixin class $AmortizationEntryCopyWith<$Res>  {
  factory $AmortizationEntryCopyWith(AmortizationEntry value, $Res Function(AmortizationEntry) _then) = _$AmortizationEntryCopyWithImpl;
@useResult
$Res call({
 String id, String liabilityId, int periodIndex, DateTime dueDate, Decimal principalPayment, Decimal interestPayment, Decimal remainingBalance, DateTime? paidAt, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$AmortizationEntryCopyWithImpl<$Res>
    implements $AmortizationEntryCopyWith<$Res> {
  _$AmortizationEntryCopyWithImpl(this._self, this._then);

  final AmortizationEntry _self;
  final $Res Function(AmortizationEntry) _then;

/// Create a copy of AmortizationEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? liabilityId = null,Object? periodIndex = null,Object? dueDate = null,Object? principalPayment = null,Object? interestPayment = null,Object? remainingBalance = null,Object? paidAt = freezed,Object? sync = null,}) {
  return _then(AmortizationEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,liabilityId: null == liabilityId ? _self.liabilityId : liabilityId // ignore: cast_nullable_to_non_nullable
as String,periodIndex: null == periodIndex ? _self.periodIndex : periodIndex // ignore: cast_nullable_to_non_nullable
as int,dueDate: null == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime,principalPayment: null == principalPayment ? _self.principalPayment : principalPayment // ignore: cast_nullable_to_non_nullable
as Decimal,interestPayment: null == interestPayment ? _self.interestPayment : interestPayment // ignore: cast_nullable_to_non_nullable
as Decimal,remainingBalance: null == remainingBalance ? _self.remainingBalance : remainingBalance // ignore: cast_nullable_to_non_nullable
as Decimal,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of AmortizationEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [AmortizationEntry].
extension AmortizationEntryPatterns on AmortizationEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AmortizationEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AmortizationEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AmortizationEntry value)  $default,){
final _that = this;
switch (_that) {
case _AmortizationEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AmortizationEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AmortizationEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String liabilityId,  int periodIndex,  DateTime dueDate,  Decimal principalPayment,  Decimal interestPayment,  Decimal remainingBalance,  DateTime? paidAt,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AmortizationEntry() when $default != null:
return $default(_that.id,_that.liabilityId,_that.periodIndex,_that.dueDate,_that.principalPayment,_that.interestPayment,_that.remainingBalance,_that.paidAt,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String liabilityId,  int periodIndex,  DateTime dueDate,  Decimal principalPayment,  Decimal interestPayment,  Decimal remainingBalance,  DateTime? paidAt,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _AmortizationEntry():
return $default(_that.id,_that.liabilityId,_that.periodIndex,_that.dueDate,_that.principalPayment,_that.interestPayment,_that.remainingBalance,_that.paidAt,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String liabilityId,  int periodIndex,  DateTime dueDate,  Decimal principalPayment,  Decimal interestPayment,  Decimal remainingBalance,  DateTime? paidAt,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _AmortizationEntry() when $default != null:
return $default(_that.id,_that.liabilityId,_that.periodIndex,_that.dueDate,_that.principalPayment,_that.interestPayment,_that.remainingBalance,_that.paidAt,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _AmortizationEntry implements AmortizationEntry {
  const _AmortizationEntry({required this.id, required this.liabilityId, required this.periodIndex, required this.dueDate, required this.principalPayment, required this.interestPayment, required this.remainingBalance, this.paidAt, required this.sync});
  

@override final  String id;
@override final  String liabilityId;
@override final  int periodIndex;
@override final  DateTime dueDate;
@override final  Decimal principalPayment;
@override final  Decimal interestPayment;
@override final  Decimal remainingBalance;
@override final  DateTime? paidAt;
@override final  SyncMeta sync;

/// Create a copy of AmortizationEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AmortizationEntryCopyWith<_AmortizationEntry> get copyWith => __$AmortizationEntryCopyWithImpl<_AmortizationEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AmortizationEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.liabilityId, liabilityId) || other.liabilityId == liabilityId)&&(identical(other.periodIndex, periodIndex) || other.periodIndex == periodIndex)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.principalPayment, principalPayment) || other.principalPayment == principalPayment)&&(identical(other.interestPayment, interestPayment) || other.interestPayment == interestPayment)&&(identical(other.remainingBalance, remainingBalance) || other.remainingBalance == remainingBalance)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,liabilityId,periodIndex,dueDate,principalPayment,interestPayment,remainingBalance,paidAt,sync);
}

@override
String toString() {
    return 'AmortizationEntry(id: $id, liabilityId: $liabilityId, periodIndex: $periodIndex, dueDate: $dueDate, principalPayment: $principalPayment, interestPayment: $interestPayment, remainingBalance: $remainingBalance, paidAt: $paidAt, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$AmortizationEntryCopyWith<$Res> implements $AmortizationEntryCopyWith<$Res> {
  factory _$AmortizationEntryCopyWith(_AmortizationEntry value, $Res Function(_AmortizationEntry) _then) = __$AmortizationEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String liabilityId, int periodIndex, DateTime dueDate, Decimal principalPayment, Decimal interestPayment, Decimal remainingBalance, DateTime? paidAt, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$AmortizationEntryCopyWithImpl<$Res>
    implements _$AmortizationEntryCopyWith<$Res> {
  __$AmortizationEntryCopyWithImpl(this._self, this._then);

  final _AmortizationEntry _self;
  final $Res Function(_AmortizationEntry) _then;

/// Create a copy of AmortizationEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? liabilityId = null,Object? periodIndex = null,Object? dueDate = null,Object? principalPayment = null,Object? interestPayment = null,Object? remainingBalance = null,Object? paidAt = freezed,Object? sync = null,}) {
  return _then(_AmortizationEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,liabilityId: null == liabilityId ? _self.liabilityId : liabilityId // ignore: cast_nullable_to_non_nullable
as String,periodIndex: null == periodIndex ? _self.periodIndex : periodIndex // ignore: cast_nullable_to_non_nullable
as int,dueDate: null == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime,principalPayment: null == principalPayment ? _self.principalPayment : principalPayment // ignore: cast_nullable_to_non_nullable
as Decimal,interestPayment: null == interestPayment ? _self.interestPayment : interestPayment // ignore: cast_nullable_to_non_nullable
as Decimal,remainingBalance: null == remainingBalance ? _self.remainingBalance : remainingBalance // ignore: cast_nullable_to_non_nullable
as Decimal,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of AmortizationEntry
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
