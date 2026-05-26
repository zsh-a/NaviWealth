// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Settings {

 String get userId; String get baseCurrency; AppThemeMode get themeMode; PrivacyMode get privacyMode; CostBasisMethod get costBasisMethod; SyncMeta get sync;
/// Create a copy of Settings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsCopyWith<Settings> get copyWith => _$SettingsCopyWithImpl<Settings>(this as Settings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Settings&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.privacyMode, privacyMode) || other.privacyMode == privacyMode)&&(identical(other.costBasisMethod, costBasisMethod) || other.costBasisMethod == costBasisMethod)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,userId,baseCurrency,themeMode,privacyMode,costBasisMethod,sync);

@override
String toString() {
  return 'Settings(userId: $userId, baseCurrency: $baseCurrency, themeMode: $themeMode, privacyMode: $privacyMode, costBasisMethod: $costBasisMethod, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $SettingsCopyWith<$Res>  {
  factory $SettingsCopyWith(Settings value, $Res Function(Settings) _then) = _$SettingsCopyWithImpl;
@useResult
$Res call({
 String userId, String baseCurrency, AppThemeMode themeMode, PrivacyMode privacyMode, CostBasisMethod costBasisMethod, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$SettingsCopyWithImpl<$Res>
    implements $SettingsCopyWith<$Res> {
  _$SettingsCopyWithImpl(this._self, this._then);

  final Settings _self;
  final $Res Function(Settings) _then;

/// Create a copy of Settings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? baseCurrency = null,Object? themeMode = null,Object? privacyMode = null,Object? costBasisMethod = null,Object? sync = null,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,privacyMode: null == privacyMode ? _self.privacyMode : privacyMode // ignore: cast_nullable_to_non_nullable
as PrivacyMode,costBasisMethod: null == costBasisMethod ? _self.costBasisMethod : costBasisMethod // ignore: cast_nullable_to_non_nullable
as CostBasisMethod,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Settings
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Settings].
extension SettingsPatterns on Settings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Settings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Settings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Settings value)  $default,){
final _that = this;
switch (_that) {
case _Settings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Settings value)?  $default,){
final _that = this;
switch (_that) {
case _Settings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId,  String baseCurrency,  AppThemeMode themeMode,  PrivacyMode privacyMode,  CostBasisMethod costBasisMethod,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Settings() when $default != null:
return $default(_that.userId,_that.baseCurrency,_that.themeMode,_that.privacyMode,_that.costBasisMethod,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId,  String baseCurrency,  AppThemeMode themeMode,  PrivacyMode privacyMode,  CostBasisMethod costBasisMethod,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Settings():
return $default(_that.userId,_that.baseCurrency,_that.themeMode,_that.privacyMode,_that.costBasisMethod,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId,  String baseCurrency,  AppThemeMode themeMode,  PrivacyMode privacyMode,  CostBasisMethod costBasisMethod,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Settings() when $default != null:
return $default(_that.userId,_that.baseCurrency,_that.themeMode,_that.privacyMode,_that.costBasisMethod,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Settings implements Settings {
  const _Settings({required this.userId, required this.baseCurrency, required this.themeMode, required this.privacyMode, required this.costBasisMethod, required this.sync});
  

@override final  String userId;
@override final  String baseCurrency;
@override final  AppThemeMode themeMode;
@override final  PrivacyMode privacyMode;
@override final  CostBasisMethod costBasisMethod;
@override final  SyncMeta sync;

/// Create a copy of Settings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsCopyWith<_Settings> get copyWith => __$SettingsCopyWithImpl<_Settings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Settings&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.privacyMode, privacyMode) || other.privacyMode == privacyMode)&&(identical(other.costBasisMethod, costBasisMethod) || other.costBasisMethod == costBasisMethod)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,userId,baseCurrency,themeMode,privacyMode,costBasisMethod,sync);

@override
String toString() {
  return 'Settings(userId: $userId, baseCurrency: $baseCurrency, themeMode: $themeMode, privacyMode: $privacyMode, costBasisMethod: $costBasisMethod, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$SettingsCopyWith<$Res> implements $SettingsCopyWith<$Res> {
  factory _$SettingsCopyWith(_Settings value, $Res Function(_Settings) _then) = __$SettingsCopyWithImpl;
@override @useResult
$Res call({
 String userId, String baseCurrency, AppThemeMode themeMode, PrivacyMode privacyMode, CostBasisMethod costBasisMethod, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$SettingsCopyWithImpl<$Res>
    implements _$SettingsCopyWith<$Res> {
  __$SettingsCopyWithImpl(this._self, this._then);

  final _Settings _self;
  final $Res Function(_Settings) _then;

/// Create a copy of Settings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? baseCurrency = null,Object? themeMode = null,Object? privacyMode = null,Object? costBasisMethod = null,Object? sync = null,}) {
  return _then(_Settings(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,privacyMode: null == privacyMode ? _self.privacyMode : privacyMode // ignore: cast_nullable_to_non_nullable
as PrivacyMode,costBasisMethod: null == costBasisMethod ? _self.costBasisMethod : costBasisMethod // ignore: cast_nullable_to_non_nullable
as CostBasisMethod,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Settings
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
