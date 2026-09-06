// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'liability.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Liability {

 String get id; LiabilityType get type; String get name; Decimal get principal;/// Effective annual interest rate as a fraction (e.g. `0.0485` for
/// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
/// time of last update; the UI should mark it as floating.
 Decimal get interestRate; String get currency; RepaymentMethod get paymentMethod; LiabilityRateType get rateType; String? get accountId; DateTime? get startDate; DateTime? get endDate; int? get termMonths; Decimal? get monthlyPayment;/// Day of month for credit-card statement closure (信用卡账单日). Used by
/// the optional reminder feature; ignored for installment loans.
 int? get statementDay;/// Day of month for credit-card payment due (信用卡还款日).
 int? get paymentDueDay; String? get note; SyncMeta get sync;
/// Create a copy of Liability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiabilityCopyWith<Liability> get copyWith => _$LiabilityCopyWithImpl<Liability>(this as Liability, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Liability;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Liability&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.principal, _this.principal) || other.principal == _this.principal)&&(identical(other.interestRate, _this.interestRate) || other.interestRate == _this.interestRate)&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.paymentMethod, _this.paymentMethod) || other.paymentMethod == _this.paymentMethod)&&(identical(other.rateType, _this.rateType) || other.rateType == _this.rateType)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.startDate, _this.startDate) || other.startDate == _this.startDate)&&(identical(other.endDate, _this.endDate) || other.endDate == _this.endDate)&&(identical(other.termMonths, _this.termMonths) || other.termMonths == _this.termMonths)&&(identical(other.monthlyPayment, _this.monthlyPayment) || other.monthlyPayment == _this.monthlyPayment)&&(identical(other.statementDay, _this.statementDay) || other.statementDay == _this.statementDay)&&(identical(other.paymentDueDay, _this.paymentDueDay) || other.paymentDueDay == _this.paymentDueDay)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as Liability;
  return Object.hash(runtimeType,_this.id,_this.type,_this.name,_this.principal,_this.interestRate,_this.currency,_this.paymentMethod,_this.rateType,_this.accountId,_this.startDate,_this.endDate,_this.termMonths,_this.monthlyPayment,_this.statementDay,_this.paymentDueDay,_this.note,_this.sync);
}

@override
String toString() {
  final _this = this as Liability;
  return 'Liability(id: ${_this.id}, type: ${_this.type}, name: ${_this.name}, principal: ${_this.principal}, interestRate: ${_this.interestRate}, currency: ${_this.currency}, paymentMethod: ${_this.paymentMethod}, rateType: ${_this.rateType}, accountId: ${_this.accountId}, startDate: ${_this.startDate}, endDate: ${_this.endDate}, termMonths: ${_this.termMonths}, monthlyPayment: ${_this.monthlyPayment}, statementDay: ${_this.statementDay}, paymentDueDay: ${_this.paymentDueDay}, note: ${_this.note}, sync: ${_this.sync})';
}


}

/// @nodoc
abstract mixin class $LiabilityCopyWith<$Res>  {
  factory $LiabilityCopyWith(Liability value, $Res Function(Liability) _then) = _$LiabilityCopyWithImpl;
@useResult
$Res call({
 String id, LiabilityType type, String name, Decimal principal, Decimal interestRate, String currency, RepaymentMethod paymentMethod, LiabilityRateType rateType, String? accountId, DateTime? startDate, DateTime? endDate, int? termMonths, Decimal? monthlyPayment, int? statementDay, int? paymentDueDay, String? note, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$LiabilityCopyWithImpl<$Res>
    implements $LiabilityCopyWith<$Res> {
  _$LiabilityCopyWithImpl(this._self, this._then);

  final Liability _self;
  final $Res Function(Liability) _then;

/// Create a copy of Liability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? name = null,Object? principal = null,Object? interestRate = null,Object? currency = null,Object? paymentMethod = null,Object? rateType = null,Object? accountId = freezed,Object? startDate = freezed,Object? endDate = freezed,Object? termMonths = freezed,Object? monthlyPayment = freezed,Object? statementDay = freezed,Object? paymentDueDay = freezed,Object? note = freezed,Object? sync = null,}) {
  return _then(Liability(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as LiabilityType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,principal: null == principal ? _self.principal : principal // ignore: cast_nullable_to_non_nullable
as Decimal,interestRate: null == interestRate ? _self.interestRate : interestRate // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,paymentMethod: null == paymentMethod ? _self.paymentMethod : paymentMethod // ignore: cast_nullable_to_non_nullable
as RepaymentMethod,rateType: null == rateType ? _self.rateType : rateType // ignore: cast_nullable_to_non_nullable
as LiabilityRateType,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,termMonths: freezed == termMonths ? _self.termMonths : termMonths // ignore: cast_nullable_to_non_nullable
as int?,monthlyPayment: freezed == monthlyPayment ? _self.monthlyPayment : monthlyPayment // ignore: cast_nullable_to_non_nullable
as Decimal?,statementDay: freezed == statementDay ? _self.statementDay : statementDay // ignore: cast_nullable_to_non_nullable
as int?,paymentDueDay: freezed == paymentDueDay ? _self.paymentDueDay : paymentDueDay // ignore: cast_nullable_to_non_nullable
as int?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Liability
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Liability].
extension LiabilityPatterns on Liability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Liability value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Liability() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Liability value)  $default,){
final _that = this;
switch (_that) {
case _Liability():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Liability value)?  $default,){
final _that = this;
switch (_that) {
case _Liability() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  LiabilityType type,  String name,  Decimal principal,  Decimal interestRate,  String currency,  RepaymentMethod paymentMethod,  LiabilityRateType rateType,  String? accountId,  DateTime? startDate,  DateTime? endDate,  int? termMonths,  Decimal? monthlyPayment,  int? statementDay,  int? paymentDueDay,  String? note,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Liability() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.principal,_that.interestRate,_that.currency,_that.paymentMethod,_that.rateType,_that.accountId,_that.startDate,_that.endDate,_that.termMonths,_that.monthlyPayment,_that.statementDay,_that.paymentDueDay,_that.note,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  LiabilityType type,  String name,  Decimal principal,  Decimal interestRate,  String currency,  RepaymentMethod paymentMethod,  LiabilityRateType rateType,  String? accountId,  DateTime? startDate,  DateTime? endDate,  int? termMonths,  Decimal? monthlyPayment,  int? statementDay,  int? paymentDueDay,  String? note,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Liability():
return $default(_that.id,_that.type,_that.name,_that.principal,_that.interestRate,_that.currency,_that.paymentMethod,_that.rateType,_that.accountId,_that.startDate,_that.endDate,_that.termMonths,_that.monthlyPayment,_that.statementDay,_that.paymentDueDay,_that.note,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  LiabilityType type,  String name,  Decimal principal,  Decimal interestRate,  String currency,  RepaymentMethod paymentMethod,  LiabilityRateType rateType,  String? accountId,  DateTime? startDate,  DateTime? endDate,  int? termMonths,  Decimal? monthlyPayment,  int? statementDay,  int? paymentDueDay,  String? note,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Liability() when $default != null:
return $default(_that.id,_that.type,_that.name,_that.principal,_that.interestRate,_that.currency,_that.paymentMethod,_that.rateType,_that.accountId,_that.startDate,_that.endDate,_that.termMonths,_that.monthlyPayment,_that.statementDay,_that.paymentDueDay,_that.note,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Liability implements Liability {
  const _Liability({required this.id, required this.type, required this.name, required this.principal, required this.interestRate, required this.currency, this.paymentMethod = RepaymentMethod.equalInstallment, this.rateType = LiabilityRateType.fixed, this.accountId, this.startDate, this.endDate, this.termMonths, this.monthlyPayment, this.statementDay, this.paymentDueDay, this.note, required this.sync});
  

@override final  String id;
@override final  LiabilityType type;
@override final  String name;
@override final  Decimal principal;
/// Effective annual interest rate as a fraction (e.g. `0.0485` for
/// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
/// time of last update; the UI should mark it as floating.
@override final  Decimal interestRate;
@override final  String currency;
@override@JsonKey() final  RepaymentMethod paymentMethod;
@override@JsonKey() final  LiabilityRateType rateType;
@override final  String? accountId;
@override final  DateTime? startDate;
@override final  DateTime? endDate;
@override final  int? termMonths;
@override final  Decimal? monthlyPayment;
/// Day of month for credit-card statement closure (信用卡账单日). Used by
/// the optional reminder feature; ignored for installment loans.
@override final  int? statementDay;
/// Day of month for credit-card payment due (信用卡还款日).
@override final  int? paymentDueDay;
@override final  String? note;
@override final  SyncMeta sync;

/// Create a copy of Liability
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiabilityCopyWith<_Liability> get copyWith => __$LiabilityCopyWithImpl<_Liability>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Liability&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.name, name) || other.name == name)&&(identical(other.principal, principal) || other.principal == principal)&&(identical(other.interestRate, interestRate) || other.interestRate == interestRate)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.paymentMethod, paymentMethod) || other.paymentMethod == paymentMethod)&&(identical(other.rateType, rateType) || other.rateType == rateType)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.termMonths, termMonths) || other.termMonths == termMonths)&&(identical(other.monthlyPayment, monthlyPayment) || other.monthlyPayment == monthlyPayment)&&(identical(other.statementDay, statementDay) || other.statementDay == statementDay)&&(identical(other.paymentDueDay, paymentDueDay) || other.paymentDueDay == paymentDueDay)&&(identical(other.note, note) || other.note == note)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,type,name,principal,interestRate,currency,paymentMethod,rateType,accountId,startDate,endDate,termMonths,monthlyPayment,statementDay,paymentDueDay,note,sync);
}

@override
String toString() {
    return 'Liability(id: $id, type: $type, name: $name, principal: $principal, interestRate: $interestRate, currency: $currency, paymentMethod: $paymentMethod, rateType: $rateType, accountId: $accountId, startDate: $startDate, endDate: $endDate, termMonths: $termMonths, monthlyPayment: $monthlyPayment, statementDay: $statementDay, paymentDueDay: $paymentDueDay, note: $note, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$LiabilityCopyWith<$Res> implements $LiabilityCopyWith<$Res> {
  factory _$LiabilityCopyWith(_Liability value, $Res Function(_Liability) _then) = __$LiabilityCopyWithImpl;
@override @useResult
$Res call({
 String id, LiabilityType type, String name, Decimal principal, Decimal interestRate, String currency, RepaymentMethod paymentMethod, LiabilityRateType rateType, String? accountId, DateTime? startDate, DateTime? endDate, int? termMonths, Decimal? monthlyPayment, int? statementDay, int? paymentDueDay, String? note, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$LiabilityCopyWithImpl<$Res>
    implements _$LiabilityCopyWith<$Res> {
  __$LiabilityCopyWithImpl(this._self, this._then);

  final _Liability _self;
  final $Res Function(_Liability) _then;

/// Create a copy of Liability
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? name = null,Object? principal = null,Object? interestRate = null,Object? currency = null,Object? paymentMethod = null,Object? rateType = null,Object? accountId = freezed,Object? startDate = freezed,Object? endDate = freezed,Object? termMonths = freezed,Object? monthlyPayment = freezed,Object? statementDay = freezed,Object? paymentDueDay = freezed,Object? note = freezed,Object? sync = null,}) {
  return _then(_Liability(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as LiabilityType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,principal: null == principal ? _self.principal : principal // ignore: cast_nullable_to_non_nullable
as Decimal,interestRate: null == interestRate ? _self.interestRate : interestRate // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,paymentMethod: null == paymentMethod ? _self.paymentMethod : paymentMethod // ignore: cast_nullable_to_non_nullable
as RepaymentMethod,rateType: null == rateType ? _self.rateType : rateType // ignore: cast_nullable_to_non_nullable
as LiabilityRateType,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,termMonths: freezed == termMonths ? _self.termMonths : termMonths // ignore: cast_nullable_to_non_nullable
as int?,monthlyPayment: freezed == monthlyPayment ? _self.monthlyPayment : monthlyPayment // ignore: cast_nullable_to_non_nullable
as Decimal?,statementDay: freezed == statementDay ? _self.statementDay : statementDay // ignore: cast_nullable_to_non_nullable
as int?,paymentDueDay: freezed == paymentDueDay ? _self.paymentDueDay : paymentDueDay // ignore: cast_nullable_to_non_nullable
as int?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Liability
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
