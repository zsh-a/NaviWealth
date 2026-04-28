// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'op_log.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$OpLog {
  String get id => throw _privateConstructorUsedError;
  String get ownerUserId => throw _privateConstructorUsedError;
  String get deviceId => throw _privateConstructorUsedError;
  Hlc get hlc => throw _privateConstructorUsedError;
  OpKind get op => throw _privateConstructorUsedError;
  String get entityTable => throw _privateConstructorUsedError;
  String get entityId => throw _privateConstructorUsedError;
  String? get patchJson => throw _privateConstructorUsedError;
  DateTime? get syncedAt => throw _privateConstructorUsedError;

  /// Create a copy of OpLog
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OpLogCopyWith<OpLog> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OpLogCopyWith<$Res> {
  factory $OpLogCopyWith(OpLog value, $Res Function(OpLog) then) =
      _$OpLogCopyWithImpl<$Res, OpLog>;
  @useResult
  $Res call({
    String id,
    String ownerUserId,
    String deviceId,
    Hlc hlc,
    OpKind op,
    String entityTable,
    String entityId,
    String? patchJson,
    DateTime? syncedAt,
  });
}

/// @nodoc
class _$OpLogCopyWithImpl<$Res, $Val extends OpLog>
    implements $OpLogCopyWith<$Res> {
  _$OpLogCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OpLog
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ownerUserId = null,
    Object? deviceId = null,
    Object? hlc = null,
    Object? op = null,
    Object? entityTable = null,
    Object? entityId = null,
    Object? patchJson = freezed,
    Object? syncedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            ownerUserId: null == ownerUserId
                ? _value.ownerUserId
                : ownerUserId // ignore: cast_nullable_to_non_nullable
                      as String,
            deviceId: null == deviceId
                ? _value.deviceId
                : deviceId // ignore: cast_nullable_to_non_nullable
                      as String,
            hlc: null == hlc
                ? _value.hlc
                : hlc // ignore: cast_nullable_to_non_nullable
                      as Hlc,
            op: null == op
                ? _value.op
                : op // ignore: cast_nullable_to_non_nullable
                      as OpKind,
            entityTable: null == entityTable
                ? _value.entityTable
                : entityTable // ignore: cast_nullable_to_non_nullable
                      as String,
            entityId: null == entityId
                ? _value.entityId
                : entityId // ignore: cast_nullable_to_non_nullable
                      as String,
            patchJson: freezed == patchJson
                ? _value.patchJson
                : patchJson // ignore: cast_nullable_to_non_nullable
                      as String?,
            syncedAt: freezed == syncedAt
                ? _value.syncedAt
                : syncedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OpLogImplCopyWith<$Res> implements $OpLogCopyWith<$Res> {
  factory _$$OpLogImplCopyWith(
    _$OpLogImpl value,
    $Res Function(_$OpLogImpl) then,
  ) = __$$OpLogImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String ownerUserId,
    String deviceId,
    Hlc hlc,
    OpKind op,
    String entityTable,
    String entityId,
    String? patchJson,
    DateTime? syncedAt,
  });
}

/// @nodoc
class __$$OpLogImplCopyWithImpl<$Res>
    extends _$OpLogCopyWithImpl<$Res, _$OpLogImpl>
    implements _$$OpLogImplCopyWith<$Res> {
  __$$OpLogImplCopyWithImpl(
    _$OpLogImpl _value,
    $Res Function(_$OpLogImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OpLog
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ownerUserId = null,
    Object? deviceId = null,
    Object? hlc = null,
    Object? op = null,
    Object? entityTable = null,
    Object? entityId = null,
    Object? patchJson = freezed,
    Object? syncedAt = freezed,
  }) {
    return _then(
      _$OpLogImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        ownerUserId: null == ownerUserId
            ? _value.ownerUserId
            : ownerUserId // ignore: cast_nullable_to_non_nullable
                  as String,
        deviceId: null == deviceId
            ? _value.deviceId
            : deviceId // ignore: cast_nullable_to_non_nullable
                  as String,
        hlc: null == hlc
            ? _value.hlc
            : hlc // ignore: cast_nullable_to_non_nullable
                  as Hlc,
        op: null == op
            ? _value.op
            : op // ignore: cast_nullable_to_non_nullable
                  as OpKind,
        entityTable: null == entityTable
            ? _value.entityTable
            : entityTable // ignore: cast_nullable_to_non_nullable
                  as String,
        entityId: null == entityId
            ? _value.entityId
            : entityId // ignore: cast_nullable_to_non_nullable
                  as String,
        patchJson: freezed == patchJson
            ? _value.patchJson
            : patchJson // ignore: cast_nullable_to_non_nullable
                  as String?,
        syncedAt: freezed == syncedAt
            ? _value.syncedAt
            : syncedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$OpLogImpl implements _OpLog {
  const _$OpLogImpl({
    required this.id,
    required this.ownerUserId,
    required this.deviceId,
    required this.hlc,
    required this.op,
    required this.entityTable,
    required this.entityId,
    this.patchJson,
    this.syncedAt,
  });

  @override
  final String id;
  @override
  final String ownerUserId;
  @override
  final String deviceId;
  @override
  final Hlc hlc;
  @override
  final OpKind op;
  @override
  final String entityTable;
  @override
  final String entityId;
  @override
  final String? patchJson;
  @override
  final DateTime? syncedAt;

  @override
  String toString() {
    return 'OpLog(id: $id, ownerUserId: $ownerUserId, deviceId: $deviceId, hlc: $hlc, op: $op, entityTable: $entityTable, entityId: $entityId, patchJson: $patchJson, syncedAt: $syncedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OpLogImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.ownerUserId, ownerUserId) ||
                other.ownerUserId == ownerUserId) &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            (identical(other.hlc, hlc) || other.hlc == hlc) &&
            (identical(other.op, op) || other.op == op) &&
            (identical(other.entityTable, entityTable) ||
                other.entityTable == entityTable) &&
            (identical(other.entityId, entityId) ||
                other.entityId == entityId) &&
            (identical(other.patchJson, patchJson) ||
                other.patchJson == patchJson) &&
            (identical(other.syncedAt, syncedAt) ||
                other.syncedAt == syncedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    ownerUserId,
    deviceId,
    hlc,
    op,
    entityTable,
    entityId,
    patchJson,
    syncedAt,
  );

  /// Create a copy of OpLog
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OpLogImplCopyWith<_$OpLogImpl> get copyWith =>
      __$$OpLogImplCopyWithImpl<_$OpLogImpl>(this, _$identity);
}

abstract class _OpLog implements OpLog {
  const factory _OpLog({
    required final String id,
    required final String ownerUserId,
    required final String deviceId,
    required final Hlc hlc,
    required final OpKind op,
    required final String entityTable,
    required final String entityId,
    final String? patchJson,
    final DateTime? syncedAt,
  }) = _$OpLogImpl;

  @override
  String get id;
  @override
  String get ownerUserId;
  @override
  String get deviceId;
  @override
  Hlc get hlc;
  @override
  OpKind get op;
  @override
  String get entityTable;
  @override
  String get entityId;
  @override
  String? get patchJson;
  @override
  DateTime? get syncedAt;

  /// Create a copy of OpLog
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OpLogImplCopyWith<_$OpLogImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
