// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_meta.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$SyncMeta {
  String get ownerUserId => throw _privateConstructorUsedError;
  DateTime get updatedAt => throw _privateConstructorUsedError;
  String get updatedByDevice => throw _privateConstructorUsedError;
  Hlc get hlc => throw _privateConstructorUsedError;
  DateTime? get deletedAt => throw _privateConstructorUsedError;

  /// Create a copy of SyncMeta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncMetaCopyWith<SyncMeta> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncMetaCopyWith<$Res> {
  factory $SyncMetaCopyWith(SyncMeta value, $Res Function(SyncMeta) then) =
      _$SyncMetaCopyWithImpl<$Res, SyncMeta>;
  @useResult
  $Res call({
    String ownerUserId,
    DateTime updatedAt,
    String updatedByDevice,
    Hlc hlc,
    DateTime? deletedAt,
  });
}

/// @nodoc
class _$SyncMetaCopyWithImpl<$Res, $Val extends SyncMeta>
    implements $SyncMetaCopyWith<$Res> {
  _$SyncMetaCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncMeta
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ownerUserId = null,
    Object? updatedAt = null,
    Object? updatedByDevice = null,
    Object? hlc = null,
    Object? deletedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            ownerUserId: null == ownerUserId
                ? _value.ownerUserId
                : ownerUserId // ignore: cast_nullable_to_non_nullable
                      as String,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            updatedByDevice: null == updatedByDevice
                ? _value.updatedByDevice
                : updatedByDevice // ignore: cast_nullable_to_non_nullable
                      as String,
            hlc: null == hlc
                ? _value.hlc
                : hlc // ignore: cast_nullable_to_non_nullable
                      as Hlc,
            deletedAt: freezed == deletedAt
                ? _value.deletedAt
                : deletedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SyncMetaImplCopyWith<$Res>
    implements $SyncMetaCopyWith<$Res> {
  factory _$$SyncMetaImplCopyWith(
    _$SyncMetaImpl value,
    $Res Function(_$SyncMetaImpl) then,
  ) = __$$SyncMetaImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String ownerUserId,
    DateTime updatedAt,
    String updatedByDevice,
    Hlc hlc,
    DateTime? deletedAt,
  });
}

/// @nodoc
class __$$SyncMetaImplCopyWithImpl<$Res>
    extends _$SyncMetaCopyWithImpl<$Res, _$SyncMetaImpl>
    implements _$$SyncMetaImplCopyWith<$Res> {
  __$$SyncMetaImplCopyWithImpl(
    _$SyncMetaImpl _value,
    $Res Function(_$SyncMetaImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SyncMeta
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ownerUserId = null,
    Object? updatedAt = null,
    Object? updatedByDevice = null,
    Object? hlc = null,
    Object? deletedAt = freezed,
  }) {
    return _then(
      _$SyncMetaImpl(
        ownerUserId: null == ownerUserId
            ? _value.ownerUserId
            : ownerUserId // ignore: cast_nullable_to_non_nullable
                  as String,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        updatedByDevice: null == updatedByDevice
            ? _value.updatedByDevice
            : updatedByDevice // ignore: cast_nullable_to_non_nullable
                  as String,
        hlc: null == hlc
            ? _value.hlc
            : hlc // ignore: cast_nullable_to_non_nullable
                  as Hlc,
        deletedAt: freezed == deletedAt
            ? _value.deletedAt
            : deletedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$SyncMetaImpl implements _SyncMeta {
  const _$SyncMetaImpl({
    required this.ownerUserId,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.hlc,
    this.deletedAt,
  });

  @override
  final String ownerUserId;
  @override
  final DateTime updatedAt;
  @override
  final String updatedByDevice;
  @override
  final Hlc hlc;
  @override
  final DateTime? deletedAt;

  @override
  String toString() {
    return 'SyncMeta(ownerUserId: $ownerUserId, updatedAt: $updatedAt, updatedByDevice: $updatedByDevice, hlc: $hlc, deletedAt: $deletedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncMetaImpl &&
            (identical(other.ownerUserId, ownerUserId) ||
                other.ownerUserId == ownerUserId) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.updatedByDevice, updatedByDevice) ||
                other.updatedByDevice == updatedByDevice) &&
            (identical(other.hlc, hlc) || other.hlc == hlc) &&
            (identical(other.deletedAt, deletedAt) ||
                other.deletedAt == deletedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    ownerUserId,
    updatedAt,
    updatedByDevice,
    hlc,
    deletedAt,
  );

  /// Create a copy of SyncMeta
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncMetaImplCopyWith<_$SyncMetaImpl> get copyWith =>
      __$$SyncMetaImplCopyWithImpl<_$SyncMetaImpl>(this, _$identity);
}

abstract class _SyncMeta implements SyncMeta {
  const factory _SyncMeta({
    required final String ownerUserId,
    required final DateTime updatedAt,
    required final String updatedByDevice,
    required final Hlc hlc,
    final DateTime? deletedAt,
  }) = _$SyncMetaImpl;

  @override
  String get ownerUserId;
  @override
  DateTime get updatedAt;
  @override
  String get updatedByDevice;
  @override
  Hlc get hlc;
  @override
  DateTime? get deletedAt;

  /// Create a copy of SyncMeta
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncMetaImplCopyWith<_$SyncMetaImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
