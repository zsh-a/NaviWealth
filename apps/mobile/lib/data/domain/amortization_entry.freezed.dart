// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'amortization_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$AmortizationEntry {
  String get id => throw _privateConstructorUsedError;
  String get liabilityId => throw _privateConstructorUsedError;
  int get periodIndex => throw _privateConstructorUsedError;
  DateTime get dueDate => throw _privateConstructorUsedError;
  Decimal get principalPayment => throw _privateConstructorUsedError;
  Decimal get interestPayment => throw _privateConstructorUsedError;
  Decimal get remainingBalance => throw _privateConstructorUsedError;
  DateTime? get paidAt => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of AmortizationEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AmortizationEntryCopyWith<AmortizationEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AmortizationEntryCopyWith<$Res> {
  factory $AmortizationEntryCopyWith(
    AmortizationEntry value,
    $Res Function(AmortizationEntry) then,
  ) = _$AmortizationEntryCopyWithImpl<$Res, AmortizationEntry>;
  @useResult
  $Res call({
    String id,
    String liabilityId,
    int periodIndex,
    DateTime dueDate,
    Decimal principalPayment,
    Decimal interestPayment,
    Decimal remainingBalance,
    DateTime? paidAt,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$AmortizationEntryCopyWithImpl<$Res, $Val extends AmortizationEntry>
    implements $AmortizationEntryCopyWith<$Res> {
  _$AmortizationEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AmortizationEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? liabilityId = null,
    Object? periodIndex = null,
    Object? dueDate = null,
    Object? principalPayment = null,
    Object? interestPayment = null,
    Object? remainingBalance = null,
    Object? paidAt = freezed,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            liabilityId: null == liabilityId
                ? _value.liabilityId
                : liabilityId // ignore: cast_nullable_to_non_nullable
                      as String,
            periodIndex: null == periodIndex
                ? _value.periodIndex
                : periodIndex // ignore: cast_nullable_to_non_nullable
                      as int,
            dueDate: null == dueDate
                ? _value.dueDate
                : dueDate // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            principalPayment: null == principalPayment
                ? _value.principalPayment
                : principalPayment // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            interestPayment: null == interestPayment
                ? _value.interestPayment
                : interestPayment // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            remainingBalance: null == remainingBalance
                ? _value.remainingBalance
                : remainingBalance // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            paidAt: freezed == paidAt
                ? _value.paidAt
                : paidAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of AmortizationEntry
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
abstract class _$$AmortizationEntryImplCopyWith<$Res>
    implements $AmortizationEntryCopyWith<$Res> {
  factory _$$AmortizationEntryImplCopyWith(
    _$AmortizationEntryImpl value,
    $Res Function(_$AmortizationEntryImpl) then,
  ) = __$$AmortizationEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String liabilityId,
    int periodIndex,
    DateTime dueDate,
    Decimal principalPayment,
    Decimal interestPayment,
    Decimal remainingBalance,
    DateTime? paidAt,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$AmortizationEntryImplCopyWithImpl<$Res>
    extends _$AmortizationEntryCopyWithImpl<$Res, _$AmortizationEntryImpl>
    implements _$$AmortizationEntryImplCopyWith<$Res> {
  __$$AmortizationEntryImplCopyWithImpl(
    _$AmortizationEntryImpl _value,
    $Res Function(_$AmortizationEntryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AmortizationEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? liabilityId = null,
    Object? periodIndex = null,
    Object? dueDate = null,
    Object? principalPayment = null,
    Object? interestPayment = null,
    Object? remainingBalance = null,
    Object? paidAt = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$AmortizationEntryImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        liabilityId: null == liabilityId
            ? _value.liabilityId
            : liabilityId // ignore: cast_nullable_to_non_nullable
                  as String,
        periodIndex: null == periodIndex
            ? _value.periodIndex
            : periodIndex // ignore: cast_nullable_to_non_nullable
                  as int,
        dueDate: null == dueDate
            ? _value.dueDate
            : dueDate // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        principalPayment: null == principalPayment
            ? _value.principalPayment
            : principalPayment // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        interestPayment: null == interestPayment
            ? _value.interestPayment
            : interestPayment // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        remainingBalance: null == remainingBalance
            ? _value.remainingBalance
            : remainingBalance // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        paidAt: freezed == paidAt
            ? _value.paidAt
            : paidAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        sync: null == sync
            ? _value.sync
            : sync // ignore: cast_nullable_to_non_nullable
                  as SyncMeta,
      ),
    );
  }
}

/// @nodoc

class _$AmortizationEntryImpl implements _AmortizationEntry {
  const _$AmortizationEntryImpl({
    required this.id,
    required this.liabilityId,
    required this.periodIndex,
    required this.dueDate,
    required this.principalPayment,
    required this.interestPayment,
    required this.remainingBalance,
    this.paidAt,
    required this.sync,
  });

  @override
  final String id;
  @override
  final String liabilityId;
  @override
  final int periodIndex;
  @override
  final DateTime dueDate;
  @override
  final Decimal principalPayment;
  @override
  final Decimal interestPayment;
  @override
  final Decimal remainingBalance;
  @override
  final DateTime? paidAt;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'AmortizationEntry(id: $id, liabilityId: $liabilityId, periodIndex: $periodIndex, dueDate: $dueDate, principalPayment: $principalPayment, interestPayment: $interestPayment, remainingBalance: $remainingBalance, paidAt: $paidAt, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AmortizationEntryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.liabilityId, liabilityId) ||
                other.liabilityId == liabilityId) &&
            (identical(other.periodIndex, periodIndex) ||
                other.periodIndex == periodIndex) &&
            (identical(other.dueDate, dueDate) || other.dueDate == dueDate) &&
            (identical(other.principalPayment, principalPayment) ||
                other.principalPayment == principalPayment) &&
            (identical(other.interestPayment, interestPayment) ||
                other.interestPayment == interestPayment) &&
            (identical(other.remainingBalance, remainingBalance) ||
                other.remainingBalance == remainingBalance) &&
            (identical(other.paidAt, paidAt) || other.paidAt == paidAt) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    liabilityId,
    periodIndex,
    dueDate,
    principalPayment,
    interestPayment,
    remainingBalance,
    paidAt,
    sync,
  );

  /// Create a copy of AmortizationEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AmortizationEntryImplCopyWith<_$AmortizationEntryImpl> get copyWith =>
      __$$AmortizationEntryImplCopyWithImpl<_$AmortizationEntryImpl>(
        this,
        _$identity,
      );
}

abstract class _AmortizationEntry implements AmortizationEntry {
  const factory _AmortizationEntry({
    required final String id,
    required final String liabilityId,
    required final int periodIndex,
    required final DateTime dueDate,
    required final Decimal principalPayment,
    required final Decimal interestPayment,
    required final Decimal remainingBalance,
    final DateTime? paidAt,
    required final SyncMeta sync,
  }) = _$AmortizationEntryImpl;

  @override
  String get id;
  @override
  String get liabilityId;
  @override
  int get periodIndex;
  @override
  DateTime get dueDate;
  @override
  Decimal get principalPayment;
  @override
  Decimal get interestPayment;
  @override
  Decimal get remainingBalance;
  @override
  DateTime? get paidAt;
  @override
  SyncMeta get sync;

  /// Create a copy of AmortizationEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AmortizationEntryImplCopyWith<_$AmortizationEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
