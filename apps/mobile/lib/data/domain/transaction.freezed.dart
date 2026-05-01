// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Transaction {

 String get id; String get accountId; String? get assetId; TransactionType get type; Decimal get quantity; Decimal get price; String get currency; DateTime get tradeDate; DateTime? get settleDate; Decimal? get fee; Decimal? get tax; String? get counterAccountId; String? get lotId; String? get note; SyncMeta get sync;
/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransactionCopyWith<Transaction> get copyWith => _$TransactionCopyWithImpl<Transaction>(this as Transaction, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Transaction&&(identical(other.id, id) || other.id == id)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.type, type) || other.type == type)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.tradeDate, tradeDate) || other.tradeDate == tradeDate)&&(identical(other.settleDate, settleDate) || other.settleDate == settleDate)&&(identical(other.fee, fee) || other.fee == fee)&&(identical(other.tax, tax) || other.tax == tax)&&(identical(other.counterAccountId, counterAccountId) || other.counterAccountId == counterAccountId)&&(identical(other.lotId, lotId) || other.lotId == lotId)&&(identical(other.note, note) || other.note == note)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,accountId,assetId,type,quantity,price,currency,tradeDate,settleDate,fee,tax,counterAccountId,lotId,note,sync);

@override
String toString() {
  return 'Transaction(id: $id, accountId: $accountId, assetId: $assetId, type: $type, quantity: $quantity, price: $price, currency: $currency, tradeDate: $tradeDate, settleDate: $settleDate, fee: $fee, tax: $tax, counterAccountId: $counterAccountId, lotId: $lotId, note: $note, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $TransactionCopyWith<$Res>  {
  factory $TransactionCopyWith(Transaction value, $Res Function(Transaction) _then) = _$TransactionCopyWithImpl;
@useResult
$Res call({
 String id, String accountId, String? assetId, TransactionType type, Decimal quantity, Decimal price, String currency, DateTime tradeDate, DateTime? settleDate, Decimal? fee, Decimal? tax, String? counterAccountId, String? lotId, String? note, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$TransactionCopyWithImpl<$Res>
    implements $TransactionCopyWith<$Res> {
  _$TransactionCopyWithImpl(this._self, this._then);

  final Transaction _self;
  final $Res Function(Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? accountId = null,Object? assetId = freezed,Object? type = null,Object? quantity = null,Object? price = null,Object? currency = null,Object? tradeDate = null,Object? settleDate = freezed,Object? fee = freezed,Object? tax = freezed,Object? counterAccountId = freezed,Object? lotId = freezed,Object? note = freezed,Object? sync = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,assetId: freezed == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TransactionType,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Decimal,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,tradeDate: null == tradeDate ? _self.tradeDate : tradeDate // ignore: cast_nullable_to_non_nullable
as DateTime,settleDate: freezed == settleDate ? _self.settleDate : settleDate // ignore: cast_nullable_to_non_nullable
as DateTime?,fee: freezed == fee ? _self.fee : fee // ignore: cast_nullable_to_non_nullable
as Decimal?,tax: freezed == tax ? _self.tax : tax // ignore: cast_nullable_to_non_nullable
as Decimal?,counterAccountId: freezed == counterAccountId ? _self.counterAccountId : counterAccountId // ignore: cast_nullable_to_non_nullable
as String?,lotId: freezed == lotId ? _self.lotId : lotId // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Transaction].
extension TransactionPatterns on Transaction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Transaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Transaction value)  $default,){
final _that = this;
switch (_that) {
case _Transaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Transaction value)?  $default,){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String accountId,  String? assetId,  TransactionType type,  Decimal quantity,  Decimal price,  String currency,  DateTime tradeDate,  DateTime? settleDate,  Decimal? fee,  Decimal? tax,  String? counterAccountId,  String? lotId,  String? note,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.accountId,_that.assetId,_that.type,_that.quantity,_that.price,_that.currency,_that.tradeDate,_that.settleDate,_that.fee,_that.tax,_that.counterAccountId,_that.lotId,_that.note,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String accountId,  String? assetId,  TransactionType type,  Decimal quantity,  Decimal price,  String currency,  DateTime tradeDate,  DateTime? settleDate,  Decimal? fee,  Decimal? tax,  String? counterAccountId,  String? lotId,  String? note,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Transaction():
return $default(_that.id,_that.accountId,_that.assetId,_that.type,_that.quantity,_that.price,_that.currency,_that.tradeDate,_that.settleDate,_that.fee,_that.tax,_that.counterAccountId,_that.lotId,_that.note,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String accountId,  String? assetId,  TransactionType type,  Decimal quantity,  Decimal price,  String currency,  DateTime tradeDate,  DateTime? settleDate,  Decimal? fee,  Decimal? tax,  String? counterAccountId,  String? lotId,  String? note,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.accountId,_that.assetId,_that.type,_that.quantity,_that.price,_that.currency,_that.tradeDate,_that.settleDate,_that.fee,_that.tax,_that.counterAccountId,_that.lotId,_that.note,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Transaction implements Transaction {
  const _Transaction({required this.id, required this.accountId, this.assetId, required this.type, required this.quantity, required this.price, required this.currency, required this.tradeDate, this.settleDate, this.fee, this.tax, this.counterAccountId, this.lotId, this.note, required this.sync});
  

@override final  String id;
@override final  String accountId;
@override final  String? assetId;
@override final  TransactionType type;
@override final  Decimal quantity;
@override final  Decimal price;
@override final  String currency;
@override final  DateTime tradeDate;
@override final  DateTime? settleDate;
@override final  Decimal? fee;
@override final  Decimal? tax;
@override final  String? counterAccountId;
@override final  String? lotId;
@override final  String? note;
@override final  SyncMeta sync;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransactionCopyWith<_Transaction> get copyWith => __$TransactionCopyWithImpl<_Transaction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Transaction&&(identical(other.id, id) || other.id == id)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.assetId, assetId) || other.assetId == assetId)&&(identical(other.type, type) || other.type == type)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.tradeDate, tradeDate) || other.tradeDate == tradeDate)&&(identical(other.settleDate, settleDate) || other.settleDate == settleDate)&&(identical(other.fee, fee) || other.fee == fee)&&(identical(other.tax, tax) || other.tax == tax)&&(identical(other.counterAccountId, counterAccountId) || other.counterAccountId == counterAccountId)&&(identical(other.lotId, lotId) || other.lotId == lotId)&&(identical(other.note, note) || other.note == note)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,accountId,assetId,type,quantity,price,currency,tradeDate,settleDate,fee,tax,counterAccountId,lotId,note,sync);

@override
String toString() {
  return 'Transaction(id: $id, accountId: $accountId, assetId: $assetId, type: $type, quantity: $quantity, price: $price, currency: $currency, tradeDate: $tradeDate, settleDate: $settleDate, fee: $fee, tax: $tax, counterAccountId: $counterAccountId, lotId: $lotId, note: $note, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$TransactionCopyWith<$Res> implements $TransactionCopyWith<$Res> {
  factory _$TransactionCopyWith(_Transaction value, $Res Function(_Transaction) _then) = __$TransactionCopyWithImpl;
@override @useResult
$Res call({
 String id, String accountId, String? assetId, TransactionType type, Decimal quantity, Decimal price, String currency, DateTime tradeDate, DateTime? settleDate, Decimal? fee, Decimal? tax, String? counterAccountId, String? lotId, String? note, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$TransactionCopyWithImpl<$Res>
    implements _$TransactionCopyWith<$Res> {
  __$TransactionCopyWithImpl(this._self, this._then);

  final _Transaction _self;
  final $Res Function(_Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? accountId = null,Object? assetId = freezed,Object? type = null,Object? quantity = null,Object? price = null,Object? currency = null,Object? tradeDate = null,Object? settleDate = freezed,Object? fee = freezed,Object? tax = freezed,Object? counterAccountId = freezed,Object? lotId = freezed,Object? note = freezed,Object? sync = null,}) {
  return _then(_Transaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,assetId: freezed == assetId ? _self.assetId : assetId // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as TransactionType,quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Decimal,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as Decimal,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,tradeDate: null == tradeDate ? _self.tradeDate : tradeDate // ignore: cast_nullable_to_non_nullable
as DateTime,settleDate: freezed == settleDate ? _self.settleDate : settleDate // ignore: cast_nullable_to_non_nullable
as DateTime?,fee: freezed == fee ? _self.fee : fee // ignore: cast_nullable_to_non_nullable
as Decimal?,tax: freezed == tax ? _self.tax : tax // ignore: cast_nullable_to_non_nullable
as Decimal?,counterAccountId: freezed == counterAccountId ? _self.counterAccountId : counterAccountId // ignore: cast_nullable_to_non_nullable
as String?,lotId: freezed == lotId ? _self.lotId : lotId // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Transaction
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
