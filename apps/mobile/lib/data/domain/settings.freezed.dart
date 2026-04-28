// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Settings {
  String get userId => throw _privateConstructorUsedError;
  String get baseCurrency => throw _privateConstructorUsedError;
  AppThemeMode get themeMode => throw _privateConstructorUsedError;
  PrivacyMode get privacyMode => throw _privateConstructorUsedError;
  CostBasisMethod get costBasisMethod => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SettingsCopyWith<Settings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SettingsCopyWith<$Res> {
  factory $SettingsCopyWith(Settings value, $Res Function(Settings) then) =
      _$SettingsCopyWithImpl<$Res, Settings>;
  @useResult
  $Res call({
    String userId,
    String baseCurrency,
    AppThemeMode themeMode,
    PrivacyMode privacyMode,
    CostBasisMethod costBasisMethod,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$SettingsCopyWithImpl<$Res, $Val extends Settings>
    implements $SettingsCopyWith<$Res> {
  _$SettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? baseCurrency = null,
    Object? themeMode = null,
    Object? privacyMode = null,
    Object? costBasisMethod = null,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            userId: null == userId
                ? _value.userId
                : userId // ignore: cast_nullable_to_non_nullable
                      as String,
            baseCurrency: null == baseCurrency
                ? _value.baseCurrency
                : baseCurrency // ignore: cast_nullable_to_non_nullable
                      as String,
            themeMode: null == themeMode
                ? _value.themeMode
                : themeMode // ignore: cast_nullable_to_non_nullable
                      as AppThemeMode,
            privacyMode: null == privacyMode
                ? _value.privacyMode
                : privacyMode // ignore: cast_nullable_to_non_nullable
                      as PrivacyMode,
            costBasisMethod: null == costBasisMethod
                ? _value.costBasisMethod
                : costBasisMethod // ignore: cast_nullable_to_non_nullable
                      as CostBasisMethod,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SyncMetaCopyWith<$Res> get sync {
    return $SyncMetaCopyWith<$Res>(_value.sync, (value) {
      return _then(_value.copyWith(sync: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SettingsImplCopyWith<$Res>
    implements $SettingsCopyWith<$Res> {
  factory _$$SettingsImplCopyWith(
    _$SettingsImpl value,
    $Res Function(_$SettingsImpl) then,
  ) = __$$SettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String userId,
    String baseCurrency,
    AppThemeMode themeMode,
    PrivacyMode privacyMode,
    CostBasisMethod costBasisMethod,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$SettingsImplCopyWithImpl<$Res>
    extends _$SettingsCopyWithImpl<$Res, _$SettingsImpl>
    implements _$$SettingsImplCopyWith<$Res> {
  __$$SettingsImplCopyWithImpl(
    _$SettingsImpl _value,
    $Res Function(_$SettingsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? baseCurrency = null,
    Object? themeMode = null,
    Object? privacyMode = null,
    Object? costBasisMethod = null,
    Object? sync = null,
  }) {
    return _then(
      _$SettingsImpl(
        userId: null == userId
            ? _value.userId
            : userId // ignore: cast_nullable_to_non_nullable
                  as String,
        baseCurrency: null == baseCurrency
            ? _value.baseCurrency
            : baseCurrency // ignore: cast_nullable_to_non_nullable
                  as String,
        themeMode: null == themeMode
            ? _value.themeMode
            : themeMode // ignore: cast_nullable_to_non_nullable
                  as AppThemeMode,
        privacyMode: null == privacyMode
            ? _value.privacyMode
            : privacyMode // ignore: cast_nullable_to_non_nullable
                  as PrivacyMode,
        costBasisMethod: null == costBasisMethod
            ? _value.costBasisMethod
            : costBasisMethod // ignore: cast_nullable_to_non_nullable
                  as CostBasisMethod,
        sync: null == sync
            ? _value.sync
            : sync // ignore: cast_nullable_to_non_nullable
                  as SyncMeta,
      ),
    );
  }
}

/// @nodoc

class _$SettingsImpl implements _Settings {
  const _$SettingsImpl({
    required this.userId,
    required this.baseCurrency,
    required this.themeMode,
    required this.privacyMode,
    required this.costBasisMethod,
    required this.sync,
  });

  @override
  final String userId;
  @override
  final String baseCurrency;
  @override
  final AppThemeMode themeMode;
  @override
  final PrivacyMode privacyMode;
  @override
  final CostBasisMethod costBasisMethod;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Settings(userId: $userId, baseCurrency: $baseCurrency, themeMode: $themeMode, privacyMode: $privacyMode, costBasisMethod: $costBasisMethod, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SettingsImpl &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.baseCurrency, baseCurrency) ||
                other.baseCurrency == baseCurrency) &&
            (identical(other.themeMode, themeMode) ||
                other.themeMode == themeMode) &&
            (identical(other.privacyMode, privacyMode) ||
                other.privacyMode == privacyMode) &&
            (identical(other.costBasisMethod, costBasisMethod) ||
                other.costBasisMethod == costBasisMethod) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    userId,
    baseCurrency,
    themeMode,
    privacyMode,
    costBasisMethod,
    sync,
  );

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SettingsImplCopyWith<_$SettingsImpl> get copyWith =>
      __$$SettingsImplCopyWithImpl<_$SettingsImpl>(this, _$identity);
}

abstract class _Settings implements Settings {
  const factory _Settings({
    required final String userId,
    required final String baseCurrency,
    required final AppThemeMode themeMode,
    required final PrivacyMode privacyMode,
    required final CostBasisMethod costBasisMethod,
    required final SyncMeta sync,
  }) = _$SettingsImpl;

  @override
  String get userId;
  @override
  String get baseCurrency;
  @override
  AppThemeMode get themeMode;
  @override
  PrivacyMode get privacyMode;
  @override
  CostBasisMethod get costBasisMethod;
  @override
  SyncMeta get sync;

  /// Create a copy of Settings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SettingsImplCopyWith<_$SettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
