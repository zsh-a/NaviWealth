// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Tag {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  TagKind get kind => throw _privateConstructorUsedError;
  String? get color => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Tag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TagCopyWith<Tag> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TagCopyWith<$Res> {
  factory $TagCopyWith(Tag value, $Res Function(Tag) then) =
      _$TagCopyWithImpl<$Res, Tag>;
  @useResult
  $Res call({
    String id,
    String name,
    TagKind kind,
    String? color,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$TagCopyWithImpl<$Res, $Val extends Tag> implements $TagCopyWith<$Res> {
  _$TagCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Tag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? kind = null,
    Object? color = freezed,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            kind: null == kind
                ? _value.kind
                : kind // ignore: cast_nullable_to_non_nullable
                      as TagKind,
            color: freezed == color
                ? _value.color
                : color // ignore: cast_nullable_to_non_nullable
                      as String?,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of Tag
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
abstract class _$$TagImplCopyWith<$Res> implements $TagCopyWith<$Res> {
  factory _$$TagImplCopyWith(_$TagImpl value, $Res Function(_$TagImpl) then) =
      __$$TagImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    TagKind kind,
    String? color,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$TagImplCopyWithImpl<$Res> extends _$TagCopyWithImpl<$Res, _$TagImpl>
    implements _$$TagImplCopyWith<$Res> {
  __$$TagImplCopyWithImpl(_$TagImpl _value, $Res Function(_$TagImpl) _then)
    : super(_value, _then);

  /// Create a copy of Tag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? kind = null,
    Object? color = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$TagImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        kind: null == kind
            ? _value.kind
            : kind // ignore: cast_nullable_to_non_nullable
                  as TagKind,
        color: freezed == color
            ? _value.color
            : color // ignore: cast_nullable_to_non_nullable
                  as String?,
        sync: null == sync
            ? _value.sync
            : sync // ignore: cast_nullable_to_non_nullable
                  as SyncMeta,
      ),
    );
  }
}

/// @nodoc

class _$TagImpl implements _Tag {
  const _$TagImpl({
    required this.id,
    required this.name,
    required this.kind,
    this.color,
    required this.sync,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final TagKind kind;
  @override
  final String? color;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Tag(id: $id, name: $name, kind: $kind, color: $color, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TagImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, name, kind, color, sync);

  /// Create a copy of Tag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TagImplCopyWith<_$TagImpl> get copyWith =>
      __$$TagImplCopyWithImpl<_$TagImpl>(this, _$identity);
}

abstract class _Tag implements Tag {
  const factory _Tag({
    required final String id,
    required final String name,
    required final TagKind kind,
    final String? color,
    required final SyncMeta sync,
  }) = _$TagImpl;

  @override
  String get id;
  @override
  String get name;
  @override
  TagKind get kind;
  @override
  String? get color;
  @override
  SyncMeta get sync;

  /// Create a copy of Tag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TagImplCopyWith<_$TagImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$TagLink {
  String get id => throw _privateConstructorUsedError;
  String get tagId => throw _privateConstructorUsedError;
  String get entityTable => throw _privateConstructorUsedError;
  String get entityId => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of TagLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TagLinkCopyWith<TagLink> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TagLinkCopyWith<$Res> {
  factory $TagLinkCopyWith(TagLink value, $Res Function(TagLink) then) =
      _$TagLinkCopyWithImpl<$Res, TagLink>;
  @useResult
  $Res call({
    String id,
    String tagId,
    String entityTable,
    String entityId,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$TagLinkCopyWithImpl<$Res, $Val extends TagLink>
    implements $TagLinkCopyWith<$Res> {
  _$TagLinkCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TagLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tagId = null,
    Object? entityTable = null,
    Object? entityId = null,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            tagId: null == tagId
                ? _value.tagId
                : tagId // ignore: cast_nullable_to_non_nullable
                      as String,
            entityTable: null == entityTable
                ? _value.entityTable
                : entityTable // ignore: cast_nullable_to_non_nullable
                      as String,
            entityId: null == entityId
                ? _value.entityId
                : entityId // ignore: cast_nullable_to_non_nullable
                      as String,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of TagLink
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
abstract class _$$TagLinkImplCopyWith<$Res> implements $TagLinkCopyWith<$Res> {
  factory _$$TagLinkImplCopyWith(
    _$TagLinkImpl value,
    $Res Function(_$TagLinkImpl) then,
  ) = __$$TagLinkImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String tagId,
    String entityTable,
    String entityId,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$TagLinkImplCopyWithImpl<$Res>
    extends _$TagLinkCopyWithImpl<$Res, _$TagLinkImpl>
    implements _$$TagLinkImplCopyWith<$Res> {
  __$$TagLinkImplCopyWithImpl(
    _$TagLinkImpl _value,
    $Res Function(_$TagLinkImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TagLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tagId = null,
    Object? entityTable = null,
    Object? entityId = null,
    Object? sync = null,
  }) {
    return _then(
      _$TagLinkImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        tagId: null == tagId
            ? _value.tagId
            : tagId // ignore: cast_nullable_to_non_nullable
                  as String,
        entityTable: null == entityTable
            ? _value.entityTable
            : entityTable // ignore: cast_nullable_to_non_nullable
                  as String,
        entityId: null == entityId
            ? _value.entityId
            : entityId // ignore: cast_nullable_to_non_nullable
                  as String,
        sync: null == sync
            ? _value.sync
            : sync // ignore: cast_nullable_to_non_nullable
                  as SyncMeta,
      ),
    );
  }
}

/// @nodoc

class _$TagLinkImpl implements _TagLink {
  const _$TagLinkImpl({
    required this.id,
    required this.tagId,
    required this.entityTable,
    required this.entityId,
    required this.sync,
  });

  @override
  final String id;
  @override
  final String tagId;
  @override
  final String entityTable;
  @override
  final String entityId;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'TagLink(id: $id, tagId: $tagId, entityTable: $entityTable, entityId: $entityId, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TagLinkImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tagId, tagId) || other.tagId == tagId) &&
            (identical(other.entityTable, entityTable) ||
                other.entityTable == entityTable) &&
            (identical(other.entityId, entityId) ||
                other.entityId == entityId) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, tagId, entityTable, entityId, sync);

  /// Create a copy of TagLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TagLinkImplCopyWith<_$TagLinkImpl> get copyWith =>
      __$$TagLinkImplCopyWithImpl<_$TagLinkImpl>(this, _$identity);
}

abstract class _TagLink implements TagLink {
  const factory _TagLink({
    required final String id,
    required final String tagId,
    required final String entityTable,
    required final String entityId,
    required final SyncMeta sync,
  }) = _$TagLinkImpl;

  @override
  String get id;
  @override
  String get tagId;
  @override
  String get entityTable;
  @override
  String get entityId;
  @override
  SyncMeta get sync;

  /// Create a copy of TagLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TagLinkImplCopyWith<_$TagLinkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
