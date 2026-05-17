// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cash_flow_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CashFlowEvent {

 String get journalEntryId; DateTime get date; CashFlowKind get kind;/// Signed amount in the active base currency. Positive means cash moves
/// into user asset accounts; negative means cash leaves them.
 Decimal get signedAmount;/// Signed amount in [currency], before any base-currency conversion.
 Decimal get originalAmount; String get currency;/// User asset account whose cash leg best represents this flow.
 String get accountId; AccountSide get counterAccountSide; bool get isForecast;
/// Create a copy of CashFlowEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CashFlowEventCopyWith<CashFlowEvent> get copyWith => _$CashFlowEventCopyWithImpl<CashFlowEvent>(this as CashFlowEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CashFlowEvent&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.date, date) || other.date == date)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.signedAmount, signedAmount) || other.signedAmount == signedAmount)&&(identical(other.originalAmount, originalAmount) || other.originalAmount == originalAmount)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.counterAccountSide, counterAccountSide) || other.counterAccountSide == counterAccountSide)&&(identical(other.isForecast, isForecast) || other.isForecast == isForecast));
}


@override
int get hashCode => Object.hash(runtimeType,journalEntryId,date,kind,signedAmount,originalAmount,currency,accountId,counterAccountSide,isForecast);

@override
String toString() {
  return 'CashFlowEvent(journalEntryId: $journalEntryId, date: $date, kind: $kind, signedAmount: $signedAmount, originalAmount: $originalAmount, currency: $currency, accountId: $accountId, counterAccountSide: $counterAccountSide, isForecast: $isForecast)';
}


}

/// @nodoc
abstract mixin class $CashFlowEventCopyWith<$Res>  {
  factory $CashFlowEventCopyWith(CashFlowEvent value, $Res Function(CashFlowEvent) _then) = _$CashFlowEventCopyWithImpl;
@useResult
$Res call({
 String journalEntryId, DateTime date, CashFlowKind kind, Decimal signedAmount, Decimal originalAmount, String currency, String accountId, AccountSide counterAccountSide, bool isForecast
});




}
/// @nodoc
class _$CashFlowEventCopyWithImpl<$Res>
    implements $CashFlowEventCopyWith<$Res> {
  _$CashFlowEventCopyWithImpl(this._self, this._then);

  final CashFlowEvent _self;
  final $Res Function(CashFlowEvent) _then;

/// Create a copy of CashFlowEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? journalEntryId = null,Object? date = null,Object? kind = null,Object? signedAmount = null,Object? originalAmount = null,Object? currency = null,Object? accountId = null,Object? counterAccountSide = null,Object? isForecast = null,}) {
  return _then(_self.copyWith(
journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as CashFlowKind,signedAmount: null == signedAmount ? _self.signedAmount : signedAmount // ignore: cast_nullable_to_non_nullable
as Decimal,originalAmount: null == originalAmount ? _self.originalAmount : originalAmount // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,counterAccountSide: null == counterAccountSide ? _self.counterAccountSide : counterAccountSide // ignore: cast_nullable_to_non_nullable
as AccountSide,isForecast: null == isForecast ? _self.isForecast : isForecast // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CashFlowEvent].
extension CashFlowEventPatterns on CashFlowEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CashFlowEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CashFlowEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CashFlowEvent value)  $default,){
final _that = this;
switch (_that) {
case _CashFlowEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CashFlowEvent value)?  $default,){
final _that = this;
switch (_that) {
case _CashFlowEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String journalEntryId,  DateTime date,  CashFlowKind kind,  Decimal signedAmount,  Decimal originalAmount,  String currency,  String accountId,  AccountSide counterAccountSide,  bool isForecast)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CashFlowEvent() when $default != null:
return $default(_that.journalEntryId,_that.date,_that.kind,_that.signedAmount,_that.originalAmount,_that.currency,_that.accountId,_that.counterAccountSide,_that.isForecast);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String journalEntryId,  DateTime date,  CashFlowKind kind,  Decimal signedAmount,  Decimal originalAmount,  String currency,  String accountId,  AccountSide counterAccountSide,  bool isForecast)  $default,) {final _that = this;
switch (_that) {
case _CashFlowEvent():
return $default(_that.journalEntryId,_that.date,_that.kind,_that.signedAmount,_that.originalAmount,_that.currency,_that.accountId,_that.counterAccountSide,_that.isForecast);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String journalEntryId,  DateTime date,  CashFlowKind kind,  Decimal signedAmount,  Decimal originalAmount,  String currency,  String accountId,  AccountSide counterAccountSide,  bool isForecast)?  $default,) {final _that = this;
switch (_that) {
case _CashFlowEvent() when $default != null:
return $default(_that.journalEntryId,_that.date,_that.kind,_that.signedAmount,_that.originalAmount,_that.currency,_that.accountId,_that.counterAccountSide,_that.isForecast);case _:
  return null;

}
}

}

/// @nodoc


class _CashFlowEvent implements CashFlowEvent {
  const _CashFlowEvent({required this.journalEntryId, required this.date, required this.kind, required this.signedAmount, required this.originalAmount, required this.currency, required this.accountId, required this.counterAccountSide, this.isForecast = false});
  

@override final  String journalEntryId;
@override final  DateTime date;
@override final  CashFlowKind kind;
/// Signed amount in the active base currency. Positive means cash moves
/// into user asset accounts; negative means cash leaves them.
@override final  Decimal signedAmount;
/// Signed amount in [currency], before any base-currency conversion.
@override final  Decimal originalAmount;
@override final  String currency;
/// User asset account whose cash leg best represents this flow.
@override final  String accountId;
@override final  AccountSide counterAccountSide;
@override@JsonKey() final  bool isForecast;

/// Create a copy of CashFlowEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CashFlowEventCopyWith<_CashFlowEvent> get copyWith => __$CashFlowEventCopyWithImpl<_CashFlowEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CashFlowEvent&&(identical(other.journalEntryId, journalEntryId) || other.journalEntryId == journalEntryId)&&(identical(other.date, date) || other.date == date)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.signedAmount, signedAmount) || other.signedAmount == signedAmount)&&(identical(other.originalAmount, originalAmount) || other.originalAmount == originalAmount)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.counterAccountSide, counterAccountSide) || other.counterAccountSide == counterAccountSide)&&(identical(other.isForecast, isForecast) || other.isForecast == isForecast));
}


@override
int get hashCode => Object.hash(runtimeType,journalEntryId,date,kind,signedAmount,originalAmount,currency,accountId,counterAccountSide,isForecast);

@override
String toString() {
  return 'CashFlowEvent(journalEntryId: $journalEntryId, date: $date, kind: $kind, signedAmount: $signedAmount, originalAmount: $originalAmount, currency: $currency, accountId: $accountId, counterAccountSide: $counterAccountSide, isForecast: $isForecast)';
}


}

/// @nodoc
abstract mixin class _$CashFlowEventCopyWith<$Res> implements $CashFlowEventCopyWith<$Res> {
  factory _$CashFlowEventCopyWith(_CashFlowEvent value, $Res Function(_CashFlowEvent) _then) = __$CashFlowEventCopyWithImpl;
@override @useResult
$Res call({
 String journalEntryId, DateTime date, CashFlowKind kind, Decimal signedAmount, Decimal originalAmount, String currency, String accountId, AccountSide counterAccountSide, bool isForecast
});




}
/// @nodoc
class __$CashFlowEventCopyWithImpl<$Res>
    implements _$CashFlowEventCopyWith<$Res> {
  __$CashFlowEventCopyWithImpl(this._self, this._then);

  final _CashFlowEvent _self;
  final $Res Function(_CashFlowEvent) _then;

/// Create a copy of CashFlowEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? journalEntryId = null,Object? date = null,Object? kind = null,Object? signedAmount = null,Object? originalAmount = null,Object? currency = null,Object? accountId = null,Object? counterAccountSide = null,Object? isForecast = null,}) {
  return _then(_CashFlowEvent(
journalEntryId: null == journalEntryId ? _self.journalEntryId : journalEntryId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as CashFlowKind,signedAmount: null == signedAmount ? _self.signedAmount : signedAmount // ignore: cast_nullable_to_non_nullable
as Decimal,originalAmount: null == originalAmount ? _self.originalAmount : originalAmount // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,counterAccountSide: null == counterAccountSide ? _self.counterAccountSide : counterAccountSide // ignore: cast_nullable_to_non_nullable
as AccountSide,isForecast: null == isForecast ? _self.isForecast : isForecast // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
