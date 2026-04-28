// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'goal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Goal {
  String get id => throw _privateConstructorUsedError;
  GoalType get type => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get currency => throw _privateConstructorUsedError;
  Decimal? get targetAmount => throw _privateConstructorUsedError;
  DateTime? get targetDate => throw _privateConstructorUsedError;
  String? get targetAllocationJson => throw _privateConstructorUsedError;
  String? get note => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Goal
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GoalCopyWith<Goal> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GoalCopyWith<$Res> {
  factory $GoalCopyWith(Goal value, $Res Function(Goal) then) =
      _$GoalCopyWithImpl<$Res, Goal>;
  @useResult
  $Res call({
    String id,
    GoalType type,
    String name,
    String? currency,
    Decimal? targetAmount,
    DateTime? targetDate,
    String? targetAllocationJson,
    String? note,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$GoalCopyWithImpl<$Res, $Val extends Goal>
    implements $GoalCopyWith<$Res> {
  _$GoalCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Goal
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? name = null,
    Object? currency = freezed,
    Object? targetAmount = freezed,
    Object? targetDate = freezed,
    Object? targetAllocationJson = freezed,
    Object? note = freezed,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as GoalType,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            currency: freezed == currency
                ? _value.currency
                : currency // ignore: cast_nullable_to_non_nullable
                      as String?,
            targetAmount: freezed == targetAmount
                ? _value.targetAmount
                : targetAmount // ignore: cast_nullable_to_non_nullable
                      as Decimal?,
            targetDate: freezed == targetDate
                ? _value.targetDate
                : targetDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            targetAllocationJson: freezed == targetAllocationJson
                ? _value.targetAllocationJson
                : targetAllocationJson // ignore: cast_nullable_to_non_nullable
                      as String?,
            note: freezed == note
                ? _value.note
                : note // ignore: cast_nullable_to_non_nullable
                      as String?,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of Goal
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
abstract class _$$GoalImplCopyWith<$Res> implements $GoalCopyWith<$Res> {
  factory _$$GoalImplCopyWith(
    _$GoalImpl value,
    $Res Function(_$GoalImpl) then,
  ) = __$$GoalImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    GoalType type,
    String name,
    String? currency,
    Decimal? targetAmount,
    DateTime? targetDate,
    String? targetAllocationJson,
    String? note,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$GoalImplCopyWithImpl<$Res>
    extends _$GoalCopyWithImpl<$Res, _$GoalImpl>
    implements _$$GoalImplCopyWith<$Res> {
  __$$GoalImplCopyWithImpl(_$GoalImpl _value, $Res Function(_$GoalImpl) _then)
    : super(_value, _then);

  /// Create a copy of Goal
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? name = null,
    Object? currency = freezed,
    Object? targetAmount = freezed,
    Object? targetDate = freezed,
    Object? targetAllocationJson = freezed,
    Object? note = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$GoalImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as GoalType,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        currency: freezed == currency
            ? _value.currency
            : currency // ignore: cast_nullable_to_non_nullable
                  as String?,
        targetAmount: freezed == targetAmount
            ? _value.targetAmount
            : targetAmount // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        targetDate: freezed == targetDate
            ? _value.targetDate
            : targetDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        targetAllocationJson: freezed == targetAllocationJson
            ? _value.targetAllocationJson
            : targetAllocationJson // ignore: cast_nullable_to_non_nullable
                  as String?,
        note: freezed == note
            ? _value.note
            : note // ignore: cast_nullable_to_non_nullable
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

class _$GoalImpl implements _Goal {
  const _$GoalImpl({
    required this.id,
    required this.type,
    required this.name,
    this.currency,
    this.targetAmount,
    this.targetDate,
    this.targetAllocationJson,
    this.note,
    required this.sync,
  });

  @override
  final String id;
  @override
  final GoalType type;
  @override
  final String name;
  @override
  final String? currency;
  @override
  final Decimal? targetAmount;
  @override
  final DateTime? targetDate;
  @override
  final String? targetAllocationJson;
  @override
  final String? note;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Goal(id: $id, type: $type, name: $name, currency: $currency, targetAmount: $targetAmount, targetDate: $targetDate, targetAllocationJson: $targetAllocationJson, note: $note, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GoalImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            (identical(other.targetAmount, targetAmount) ||
                other.targetAmount == targetAmount) &&
            (identical(other.targetDate, targetDate) ||
                other.targetDate == targetDate) &&
            (identical(other.targetAllocationJson, targetAllocationJson) ||
                other.targetAllocationJson == targetAllocationJson) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    type,
    name,
    currency,
    targetAmount,
    targetDate,
    targetAllocationJson,
    note,
    sync,
  );

  /// Create a copy of Goal
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GoalImplCopyWith<_$GoalImpl> get copyWith =>
      __$$GoalImplCopyWithImpl<_$GoalImpl>(this, _$identity);
}

abstract class _Goal implements Goal {
  const factory _Goal({
    required final String id,
    required final GoalType type,
    required final String name,
    final String? currency,
    final Decimal? targetAmount,
    final DateTime? targetDate,
    final String? targetAllocationJson,
    final String? note,
    required final SyncMeta sync,
  }) = _$GoalImpl;

  @override
  String get id;
  @override
  GoalType get type;
  @override
  String get name;
  @override
  String? get currency;
  @override
  Decimal? get targetAmount;
  @override
  DateTime? get targetDate;
  @override
  String? get targetAllocationJson;
  @override
  String? get note;
  @override
  SyncMeta get sync;

  /// Create a copy of Goal
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GoalImplCopyWith<_$GoalImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
