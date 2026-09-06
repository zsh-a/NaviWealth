// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'health_metric.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HealthMetric {

/// String UUID. Stable across syncs; same convention as Finance.
 String get id;/// Wall-time the measurement is *about* (UTC). Session start for
/// sleep, calendar-day-start for daily summaries.
 DateTime get capturedAt; HealthMetricKind get kind;/// Numeric value in [unit]. See [HealthMetricKindX.defaultUnit].
 double get value;/// SI-style unit string (`'s'`, `'ms'`, `'count'`, `'bpm'`,
/// `'kcal'`, `'kg'`, `'fraction'`).
 String get unit;/// Kind-specific extra payload (sleep stages histogram, averaging
/// window, …) JSON-encoded. `null` when the row has no extras.
 String? get payloadJson;/// Best-effort device attribution (`'iPhone'`, `'Apple Watch'`,
/// `'manual'`, …). Free text — pass through from the platform
/// adapter.
 String? get sourceDevice;/// Sync metadata — owner / HLC / soft-delete tombstone. Same shape
/// as every other synced domain entity.
 SyncMeta get sync;
/// Create a copy of HealthMetric
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HealthMetricCopyWith<HealthMetric> get copyWith => _$HealthMetricCopyWithImpl<HealthMetric>(this as HealthMetric, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as HealthMetric;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HealthMetric&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.capturedAt, _this.capturedAt) || other.capturedAt == _this.capturedAt)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.value, _this.value) || other.value == _this.value)&&(identical(other.unit, _this.unit) || other.unit == _this.unit)&&(identical(other.payloadJson, _this.payloadJson) || other.payloadJson == _this.payloadJson)&&(identical(other.sourceDevice, _this.sourceDevice) || other.sourceDevice == _this.sourceDevice)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as HealthMetric;
  return Object.hash(runtimeType,_this.id,_this.capturedAt,_this.kind,_this.value,_this.unit,_this.payloadJson,_this.sourceDevice,_this.sync);
}

@override
String toString() {
  final _this = this as HealthMetric;
  return 'HealthMetric(id: ${_this.id}, capturedAt: ${_this.capturedAt}, kind: ${_this.kind}, value: ${_this.value}, unit: ${_this.unit}, payloadJson: ${_this.payloadJson}, sourceDevice: ${_this.sourceDevice}, sync: ${_this.sync})';
}


}

/// @nodoc
abstract mixin class $HealthMetricCopyWith<$Res>  {
  factory $HealthMetricCopyWith(HealthMetric value, $Res Function(HealthMetric) _then) = _$HealthMetricCopyWithImpl;
@useResult
$Res call({
 String id, DateTime capturedAt, HealthMetricKind kind, double value, String unit, String? payloadJson, String? sourceDevice, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$HealthMetricCopyWithImpl<$Res>
    implements $HealthMetricCopyWith<$Res> {
  _$HealthMetricCopyWithImpl(this._self, this._then);

  final HealthMetric _self;
  final $Res Function(HealthMetric) _then;

/// Create a copy of HealthMetric
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? capturedAt = null,Object? kind = null,Object? value = null,Object? unit = null,Object? payloadJson = freezed,Object? sourceDevice = freezed,Object? sync = null,}) {
  return _then(HealthMetric(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as HealthMetricKind,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,payloadJson: freezed == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String?,sourceDevice: freezed == sourceDevice ? _self.sourceDevice : sourceDevice // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of HealthMetric
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [HealthMetric].
extension HealthMetricPatterns on HealthMetric {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HealthMetric value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HealthMetric() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HealthMetric value)  $default,){
final _that = this;
switch (_that) {
case _HealthMetric():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HealthMetric value)?  $default,){
final _that = this;
switch (_that) {
case _HealthMetric() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime capturedAt,  HealthMetricKind kind,  double value,  String unit,  String? payloadJson,  String? sourceDevice,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HealthMetric() when $default != null:
return $default(_that.id,_that.capturedAt,_that.kind,_that.value,_that.unit,_that.payloadJson,_that.sourceDevice,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime capturedAt,  HealthMetricKind kind,  double value,  String unit,  String? payloadJson,  String? sourceDevice,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _HealthMetric():
return $default(_that.id,_that.capturedAt,_that.kind,_that.value,_that.unit,_that.payloadJson,_that.sourceDevice,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime capturedAt,  HealthMetricKind kind,  double value,  String unit,  String? payloadJson,  String? sourceDevice,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _HealthMetric() when $default != null:
return $default(_that.id,_that.capturedAt,_that.kind,_that.value,_that.unit,_that.payloadJson,_that.sourceDevice,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _HealthMetric implements HealthMetric {
  const _HealthMetric({required this.id, required this.capturedAt, required this.kind, required this.value, required this.unit, this.payloadJson, this.sourceDevice, required this.sync});
  

/// String UUID. Stable across syncs; same convention as Finance.
@override final  String id;
/// Wall-time the measurement is *about* (UTC). Session start for
/// sleep, calendar-day-start for daily summaries.
@override final  DateTime capturedAt;
@override final  HealthMetricKind kind;
/// Numeric value in [unit]. See [HealthMetricKindX.defaultUnit].
@override final  double value;
/// SI-style unit string (`'s'`, `'ms'`, `'count'`, `'bpm'`,
/// `'kcal'`, `'kg'`, `'fraction'`).
@override final  String unit;
/// Kind-specific extra payload (sleep stages histogram, averaging
/// window, …) JSON-encoded. `null` when the row has no extras.
@override final  String? payloadJson;
/// Best-effort device attribution (`'iPhone'`, `'Apple Watch'`,
/// `'manual'`, …). Free text — pass through from the platform
/// adapter.
@override final  String? sourceDevice;
/// Sync metadata — owner / HLC / soft-delete tombstone. Same shape
/// as every other synced domain entity.
@override final  SyncMeta sync;

/// Create a copy of HealthMetric
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HealthMetricCopyWith<_HealthMetric> get copyWith => __$HealthMetricCopyWithImpl<_HealthMetric>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HealthMetric&&(identical(other.id, id) || other.id == id)&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.value, value) || other.value == value)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.payloadJson, payloadJson) || other.payloadJson == payloadJson)&&(identical(other.sourceDevice, sourceDevice) || other.sourceDevice == sourceDevice)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,capturedAt,kind,value,unit,payloadJson,sourceDevice,sync);
}

@override
String toString() {
    return 'HealthMetric(id: $id, capturedAt: $capturedAt, kind: $kind, value: $value, unit: $unit, payloadJson: $payloadJson, sourceDevice: $sourceDevice, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$HealthMetricCopyWith<$Res> implements $HealthMetricCopyWith<$Res> {
  factory _$HealthMetricCopyWith(_HealthMetric value, $Res Function(_HealthMetric) _then) = __$HealthMetricCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime capturedAt, HealthMetricKind kind, double value, String unit, String? payloadJson, String? sourceDevice, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$HealthMetricCopyWithImpl<$Res>
    implements _$HealthMetricCopyWith<$Res> {
  __$HealthMetricCopyWithImpl(this._self, this._then);

  final _HealthMetric _self;
  final $Res Function(_HealthMetric) _then;

/// Create a copy of HealthMetric
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? capturedAt = null,Object? kind = null,Object? value = null,Object? unit = null,Object? payloadJson = freezed,Object? sourceDevice = freezed,Object? sync = null,}) {
  return _then(_HealthMetric(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as DateTime,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as HealthMetricKind,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,payloadJson: freezed == payloadJson ? _self.payloadJson : payloadJson // ignore: cast_nullable_to_non_nullable
as String?,sourceDevice: freezed == sourceDevice ? _self.sourceDevice : sourceDevice // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of HealthMetric
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
