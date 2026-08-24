// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'op_log.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$OpLog {

 String get id; String get ownerUserId; String get deviceId; Hlc get hlc; OpKind get op; String get entityTable; String get entityId; String? get patchJson; DateTime? get syncedAt;
/// Create a copy of OpLog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpLogCopyWith<OpLog> get copyWith => _$OpLogCopyWithImpl<OpLog>(this as OpLog, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpLog&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerUserId, ownerUserId) || other.ownerUserId == ownerUserId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.op, op) || other.op == op)&&(identical(other.entityTable, entityTable) || other.entityTable == entityTable)&&(identical(other.entityId, entityId) || other.entityId == entityId)&&(identical(other.patchJson, patchJson) || other.patchJson == patchJson)&&(identical(other.syncedAt, syncedAt) || other.syncedAt == syncedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,ownerUserId,deviceId,hlc,op,entityTable,entityId,patchJson,syncedAt);

@override
String toString() {
  return 'OpLog(id: $id, ownerUserId: $ownerUserId, deviceId: $deviceId, hlc: $hlc, op: $op, entityTable: $entityTable, entityId: $entityId, patchJson: $patchJson, syncedAt: $syncedAt)';
}


}

/// @nodoc
abstract mixin class $OpLogCopyWith<$Res>  {
  factory $OpLogCopyWith(OpLog value, $Res Function(OpLog) _then) = _$OpLogCopyWithImpl;
@useResult
$Res call({
 String id, String ownerUserId, String deviceId, Hlc hlc, OpKind op, String entityTable, String entityId, String? patchJson, DateTime? syncedAt
});




}
/// @nodoc
class _$OpLogCopyWithImpl<$Res>
    implements $OpLogCopyWith<$Res> {
  _$OpLogCopyWithImpl(this._self, this._then);

  final OpLog _self;
  final $Res Function(OpLog) _then;

/// Create a copy of OpLog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ownerUserId = null,Object? deviceId = null,Object? hlc = null,Object? op = null,Object? entityTable = null,Object? entityId = null,Object? patchJson = freezed,Object? syncedAt = freezed,}) {
  return _then(OpLog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerUserId: null == ownerUserId ? _self.ownerUserId : ownerUserId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as Hlc,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as OpKind,entityTable: null == entityTable ? _self.entityTable : entityTable // ignore: cast_nullable_to_non_nullable
as String,entityId: null == entityId ? _self.entityId : entityId // ignore: cast_nullable_to_non_nullable
as String,patchJson: freezed == patchJson ? _self.patchJson : patchJson // ignore: cast_nullable_to_non_nullable
as String?,syncedAt: freezed == syncedAt ? _self.syncedAt : syncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [OpLog].
extension OpLogPatterns on OpLog {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OpLog value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OpLog() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OpLog value)  $default,){
final _that = this;
switch (_that) {
case _OpLog():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OpLog value)?  $default,){
final _that = this;
switch (_that) {
case _OpLog() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ownerUserId,  String deviceId,  Hlc hlc,  OpKind op,  String entityTable,  String entityId,  String? patchJson,  DateTime? syncedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OpLog() when $default != null:
return $default(_that.id,_that.ownerUserId,_that.deviceId,_that.hlc,_that.op,_that.entityTable,_that.entityId,_that.patchJson,_that.syncedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ownerUserId,  String deviceId,  Hlc hlc,  OpKind op,  String entityTable,  String entityId,  String? patchJson,  DateTime? syncedAt)  $default,) {final _that = this;
switch (_that) {
case _OpLog():
return $default(_that.id,_that.ownerUserId,_that.deviceId,_that.hlc,_that.op,_that.entityTable,_that.entityId,_that.patchJson,_that.syncedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ownerUserId,  String deviceId,  Hlc hlc,  OpKind op,  String entityTable,  String entityId,  String? patchJson,  DateTime? syncedAt)?  $default,) {final _that = this;
switch (_that) {
case _OpLog() when $default != null:
return $default(_that.id,_that.ownerUserId,_that.deviceId,_that.hlc,_that.op,_that.entityTable,_that.entityId,_that.patchJson,_that.syncedAt);case _:
  return null;

}
}

}

/// @nodoc


class _OpLog implements OpLog {
  const _OpLog({required this.id, required this.ownerUserId, required this.deviceId, required this.hlc, required this.op, required this.entityTable, required this.entityId, this.patchJson, this.syncedAt});
  

@override final  String id;
@override final  String ownerUserId;
@override final  String deviceId;
@override final  Hlc hlc;
@override final  OpKind op;
@override final  String entityTable;
@override final  String entityId;
@override final  String? patchJson;
@override final  DateTime? syncedAt;

/// Create a copy of OpLog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpLogCopyWith<_OpLog> get copyWith => __$OpLogCopyWithImpl<_OpLog>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OpLog&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerUserId, ownerUserId) || other.ownerUserId == ownerUserId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.op, op) || other.op == op)&&(identical(other.entityTable, entityTable) || other.entityTable == entityTable)&&(identical(other.entityId, entityId) || other.entityId == entityId)&&(identical(other.patchJson, patchJson) || other.patchJson == patchJson)&&(identical(other.syncedAt, syncedAt) || other.syncedAt == syncedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,ownerUserId,deviceId,hlc,op,entityTable,entityId,patchJson,syncedAt);

@override
String toString() {
  return 'OpLog(id: $id, ownerUserId: $ownerUserId, deviceId: $deviceId, hlc: $hlc, op: $op, entityTable: $entityTable, entityId: $entityId, patchJson: $patchJson, syncedAt: $syncedAt)';
}


}

/// @nodoc
abstract mixin class _$OpLogCopyWith<$Res> implements $OpLogCopyWith<$Res> {
  factory _$OpLogCopyWith(_OpLog value, $Res Function(_OpLog) _then) = __$OpLogCopyWithImpl;
@override @useResult
$Res call({
 String id, String ownerUserId, String deviceId, Hlc hlc, OpKind op, String entityTable, String entityId, String? patchJson, DateTime? syncedAt
});




}
/// @nodoc
class __$OpLogCopyWithImpl<$Res>
    implements _$OpLogCopyWith<$Res> {
  __$OpLogCopyWithImpl(this._self, this._then);

  final _OpLog _self;
  final $Res Function(_OpLog) _then;

/// Create a copy of OpLog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ownerUserId = null,Object? deviceId = null,Object? hlc = null,Object? op = null,Object? entityTable = null,Object? entityId = null,Object? patchJson = freezed,Object? syncedAt = freezed,}) {
  return _then(_OpLog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerUserId: null == ownerUserId ? _self.ownerUserId : ownerUserId // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as Hlc,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as OpKind,entityTable: null == entityTable ? _self.entityTable : entityTable // ignore: cast_nullable_to_non_nullable
as String,entityId: null == entityId ? _self.entityId : entityId // ignore: cast_nullable_to_non_nullable
as String,patchJson: freezed == patchJson ? _self.patchJson : patchJson // ignore: cast_nullable_to_non_nullable
as String?,syncedAt: freezed == syncedAt ? _self.syncedAt : syncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
