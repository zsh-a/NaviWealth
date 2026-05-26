// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_meta.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncMeta {

 String get ownerUserId; DateTime get updatedAt; String get updatedByDevice; Hlc get hlc; DateTime? get deletedAt;
/// Create a copy of SyncMeta
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<SyncMeta> get copyWith => _$SyncMetaCopyWithImpl<SyncMeta>(this as SyncMeta, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncMeta&&(identical(other.ownerUserId, ownerUserId) || other.ownerUserId == ownerUserId)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.updatedByDevice, updatedByDevice) || other.updatedByDevice == updatedByDevice)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode => Object.hash(runtimeType,ownerUserId,updatedAt,updatedByDevice,hlc,deletedAt);

@override
String toString() {
  return 'SyncMeta(ownerUserId: $ownerUserId, updatedAt: $updatedAt, updatedByDevice: $updatedByDevice, hlc: $hlc, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $SyncMetaCopyWith<$Res>  {
  factory $SyncMetaCopyWith(SyncMeta value, $Res Function(SyncMeta) _then) = _$SyncMetaCopyWithImpl;
@useResult
$Res call({
 String ownerUserId, DateTime updatedAt, String updatedByDevice, Hlc hlc, DateTime? deletedAt
});




}
/// @nodoc
class _$SyncMetaCopyWithImpl<$Res>
    implements $SyncMetaCopyWith<$Res> {
  _$SyncMetaCopyWithImpl(this._self, this._then);

  final SyncMeta _self;
  final $Res Function(SyncMeta) _then;

/// Create a copy of SyncMeta
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ownerUserId = null,Object? updatedAt = null,Object? updatedByDevice = null,Object? hlc = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
ownerUserId: null == ownerUserId ? _self.ownerUserId : ownerUserId // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedByDevice: null == updatedByDevice ? _self.updatedByDevice : updatedByDevice // ignore: cast_nullable_to_non_nullable
as String,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as Hlc,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncMeta].
extension SyncMetaPatterns on SyncMeta {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncMeta value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncMeta() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncMeta value)  $default,){
final _that = this;
switch (_that) {
case _SyncMeta():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncMeta value)?  $default,){
final _that = this;
switch (_that) {
case _SyncMeta() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ownerUserId,  DateTime updatedAt,  String updatedByDevice,  Hlc hlc,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncMeta() when $default != null:
return $default(_that.ownerUserId,_that.updatedAt,_that.updatedByDevice,_that.hlc,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ownerUserId,  DateTime updatedAt,  String updatedByDevice,  Hlc hlc,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _SyncMeta():
return $default(_that.ownerUserId,_that.updatedAt,_that.updatedByDevice,_that.hlc,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ownerUserId,  DateTime updatedAt,  String updatedByDevice,  Hlc hlc,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _SyncMeta() when $default != null:
return $default(_that.ownerUserId,_that.updatedAt,_that.updatedByDevice,_that.hlc,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _SyncMeta implements SyncMeta {
  const _SyncMeta({required this.ownerUserId, required this.updatedAt, required this.updatedByDevice, required this.hlc, this.deletedAt});
  

@override final  String ownerUserId;
@override final  DateTime updatedAt;
@override final  String updatedByDevice;
@override final  Hlc hlc;
@override final  DateTime? deletedAt;

/// Create a copy of SyncMeta
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncMetaCopyWith<_SyncMeta> get copyWith => __$SyncMetaCopyWithImpl<_SyncMeta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncMeta&&(identical(other.ownerUserId, ownerUserId) || other.ownerUserId == ownerUserId)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.updatedByDevice, updatedByDevice) || other.updatedByDevice == updatedByDevice)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode => Object.hash(runtimeType,ownerUserId,updatedAt,updatedByDevice,hlc,deletedAt);

@override
String toString() {
  return 'SyncMeta(ownerUserId: $ownerUserId, updatedAt: $updatedAt, updatedByDevice: $updatedByDevice, hlc: $hlc, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$SyncMetaCopyWith<$Res> implements $SyncMetaCopyWith<$Res> {
  factory _$SyncMetaCopyWith(_SyncMeta value, $Res Function(_SyncMeta) _then) = __$SyncMetaCopyWithImpl;
@override @useResult
$Res call({
 String ownerUserId, DateTime updatedAt, String updatedByDevice, Hlc hlc, DateTime? deletedAt
});




}
/// @nodoc
class __$SyncMetaCopyWithImpl<$Res>
    implements _$SyncMetaCopyWith<$Res> {
  __$SyncMetaCopyWithImpl(this._self, this._then);

  final _SyncMeta _self;
  final $Res Function(_SyncMeta) _then;

/// Create a copy of SyncMeta
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ownerUserId = null,Object? updatedAt = null,Object? updatedByDevice = null,Object? hlc = null,Object? deletedAt = freezed,}) {
  return _then(_SyncMeta(
ownerUserId: null == ownerUserId ? _self.ownerUserId : ownerUserId // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedByDevice: null == updatedByDevice ? _self.updatedByDevice : updatedByDevice // ignore: cast_nullable_to_non_nullable
as String,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as Hlc,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
