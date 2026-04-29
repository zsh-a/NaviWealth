// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'liability.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Liability {
  String get id => throw _privateConstructorUsedError;
  LiabilityType get type => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  Decimal get principal => throw _privateConstructorUsedError;

  /// Effective annual interest rate as a fraction (e.g. `0.0485` for
  /// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
  /// time of last update; the UI should mark it as floating.
  Decimal get interestRate => throw _privateConstructorUsedError;
  String get currency => throw _privateConstructorUsedError;
  RepaymentMethod get paymentMethod => throw _privateConstructorUsedError;
  LiabilityRateType get rateType => throw _privateConstructorUsedError;
  String? get accountId => throw _privateConstructorUsedError;
  DateTime? get startDate => throw _privateConstructorUsedError;
  DateTime? get endDate => throw _privateConstructorUsedError;
  int? get termMonths => throw _privateConstructorUsedError;
  Decimal? get monthlyPayment => throw _privateConstructorUsedError;

  /// Day of month for credit-card statement closure (信用卡账单日). Used by
  /// the optional reminder feature; ignored for installment loans.
  int? get statementDay => throw _privateConstructorUsedError;

  /// Day of month for credit-card payment due (信用卡还款日).
  int? get paymentDueDay => throw _privateConstructorUsedError;
  String? get note => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Liability
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LiabilityCopyWith<Liability> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LiabilityCopyWith<$Res> {
  factory $LiabilityCopyWith(Liability value, $Res Function(Liability) then) =
      _$LiabilityCopyWithImpl<$Res, Liability>;
  @useResult
  $Res call({
    String id,
    LiabilityType type,
    String name,
    Decimal principal,
    Decimal interestRate,
    String currency,
    RepaymentMethod paymentMethod,
    LiabilityRateType rateType,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? termMonths,
    Decimal? monthlyPayment,
    int? statementDay,
    int? paymentDueDay,
    String? note,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$LiabilityCopyWithImpl<$Res, $Val extends Liability>
    implements $LiabilityCopyWith<$Res> {
  _$LiabilityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Liability
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? name = null,
    Object? principal = null,
    Object? interestRate = null,
    Object? currency = null,
    Object? paymentMethod = null,
    Object? rateType = null,
    Object? accountId = freezed,
    Object? startDate = freezed,
    Object? endDate = freezed,
    Object? termMonths = freezed,
    Object? monthlyPayment = freezed,
    Object? statementDay = freezed,
    Object? paymentDueDay = freezed,
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
                      as LiabilityType,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            principal: null == principal
                ? _value.principal
                : principal // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            interestRate: null == interestRate
                ? _value.interestRate
                : interestRate // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            currency: null == currency
                ? _value.currency
                : currency // ignore: cast_nullable_to_non_nullable
                      as String,
            paymentMethod: null == paymentMethod
                ? _value.paymentMethod
                : paymentMethod // ignore: cast_nullable_to_non_nullable
                      as RepaymentMethod,
            rateType: null == rateType
                ? _value.rateType
                : rateType // ignore: cast_nullable_to_non_nullable
                      as LiabilityRateType,
            accountId: freezed == accountId
                ? _value.accountId
                : accountId // ignore: cast_nullable_to_non_nullable
                      as String?,
            startDate: freezed == startDate
                ? _value.startDate
                : startDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            endDate: freezed == endDate
                ? _value.endDate
                : endDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            termMonths: freezed == termMonths
                ? _value.termMonths
                : termMonths // ignore: cast_nullable_to_non_nullable
                      as int?,
            monthlyPayment: freezed == monthlyPayment
                ? _value.monthlyPayment
                : monthlyPayment // ignore: cast_nullable_to_non_nullable
                      as Decimal?,
            statementDay: freezed == statementDay
                ? _value.statementDay
                : statementDay // ignore: cast_nullable_to_non_nullable
                      as int?,
            paymentDueDay: freezed == paymentDueDay
                ? _value.paymentDueDay
                : paymentDueDay // ignore: cast_nullable_to_non_nullable
                      as int?,
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

  /// Create a copy of Liability
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
abstract class _$$LiabilityImplCopyWith<$Res>
    implements $LiabilityCopyWith<$Res> {
  factory _$$LiabilityImplCopyWith(
    _$LiabilityImpl value,
    $Res Function(_$LiabilityImpl) then,
  ) = __$$LiabilityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    LiabilityType type,
    String name,
    Decimal principal,
    Decimal interestRate,
    String currency,
    RepaymentMethod paymentMethod,
    LiabilityRateType rateType,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? termMonths,
    Decimal? monthlyPayment,
    int? statementDay,
    int? paymentDueDay,
    String? note,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$LiabilityImplCopyWithImpl<$Res>
    extends _$LiabilityCopyWithImpl<$Res, _$LiabilityImpl>
    implements _$$LiabilityImplCopyWith<$Res> {
  __$$LiabilityImplCopyWithImpl(
    _$LiabilityImpl _value,
    $Res Function(_$LiabilityImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Liability
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? name = null,
    Object? principal = null,
    Object? interestRate = null,
    Object? currency = null,
    Object? paymentMethod = null,
    Object? rateType = null,
    Object? accountId = freezed,
    Object? startDate = freezed,
    Object? endDate = freezed,
    Object? termMonths = freezed,
    Object? monthlyPayment = freezed,
    Object? statementDay = freezed,
    Object? paymentDueDay = freezed,
    Object? note = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$LiabilityImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as LiabilityType,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        principal: null == principal
            ? _value.principal
            : principal // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        interestRate: null == interestRate
            ? _value.interestRate
            : interestRate // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        currency: null == currency
            ? _value.currency
            : currency // ignore: cast_nullable_to_non_nullable
                  as String,
        paymentMethod: null == paymentMethod
            ? _value.paymentMethod
            : paymentMethod // ignore: cast_nullable_to_non_nullable
                  as RepaymentMethod,
        rateType: null == rateType
            ? _value.rateType
            : rateType // ignore: cast_nullable_to_non_nullable
                  as LiabilityRateType,
        accountId: freezed == accountId
            ? _value.accountId
            : accountId // ignore: cast_nullable_to_non_nullable
                  as String?,
        startDate: freezed == startDate
            ? _value.startDate
            : startDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        endDate: freezed == endDate
            ? _value.endDate
            : endDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        termMonths: freezed == termMonths
            ? _value.termMonths
            : termMonths // ignore: cast_nullable_to_non_nullable
                  as int?,
        monthlyPayment: freezed == monthlyPayment
            ? _value.monthlyPayment
            : monthlyPayment // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        statementDay: freezed == statementDay
            ? _value.statementDay
            : statementDay // ignore: cast_nullable_to_non_nullable
                  as int?,
        paymentDueDay: freezed == paymentDueDay
            ? _value.paymentDueDay
            : paymentDueDay // ignore: cast_nullable_to_non_nullable
                  as int?,
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

class _$LiabilityImpl implements _Liability {
  const _$LiabilityImpl({
    required this.id,
    required this.type,
    required this.name,
    required this.principal,
    required this.interestRate,
    required this.currency,
    this.paymentMethod = RepaymentMethod.equalInstallment,
    this.rateType = LiabilityRateType.fixed,
    this.accountId,
    this.startDate,
    this.endDate,
    this.termMonths,
    this.monthlyPayment,
    this.statementDay,
    this.paymentDueDay,
    this.note,
    required this.sync,
  });

  @override
  final String id;
  @override
  final LiabilityType type;
  @override
  final String name;
  @override
  final Decimal principal;

  /// Effective annual interest rate as a fraction (e.g. `0.0485` for
  /// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
  /// time of last update; the UI should mark it as floating.
  @override
  final Decimal interestRate;
  @override
  final String currency;
  @override
  @JsonKey()
  final RepaymentMethod paymentMethod;
  @override
  @JsonKey()
  final LiabilityRateType rateType;
  @override
  final String? accountId;
  @override
  final DateTime? startDate;
  @override
  final DateTime? endDate;
  @override
  final int? termMonths;
  @override
  final Decimal? monthlyPayment;

  /// Day of month for credit-card statement closure (信用卡账单日). Used by
  /// the optional reminder feature; ignored for installment loans.
  @override
  final int? statementDay;

  /// Day of month for credit-card payment due (信用卡还款日).
  @override
  final int? paymentDueDay;
  @override
  final String? note;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Liability(id: $id, type: $type, name: $name, principal: $principal, interestRate: $interestRate, currency: $currency, paymentMethod: $paymentMethod, rateType: $rateType, accountId: $accountId, startDate: $startDate, endDate: $endDate, termMonths: $termMonths, monthlyPayment: $monthlyPayment, statementDay: $statementDay, paymentDueDay: $paymentDueDay, note: $note, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LiabilityImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.principal, principal) ||
                other.principal == principal) &&
            (identical(other.interestRate, interestRate) ||
                other.interestRate == interestRate) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            (identical(other.paymentMethod, paymentMethod) ||
                other.paymentMethod == paymentMethod) &&
            (identical(other.rateType, rateType) ||
                other.rateType == rateType) &&
            (identical(other.accountId, accountId) ||
                other.accountId == accountId) &&
            (identical(other.startDate, startDate) ||
                other.startDate == startDate) &&
            (identical(other.endDate, endDate) || other.endDate == endDate) &&
            (identical(other.termMonths, termMonths) ||
                other.termMonths == termMonths) &&
            (identical(other.monthlyPayment, monthlyPayment) ||
                other.monthlyPayment == monthlyPayment) &&
            (identical(other.statementDay, statementDay) ||
                other.statementDay == statementDay) &&
            (identical(other.paymentDueDay, paymentDueDay) ||
                other.paymentDueDay == paymentDueDay) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    type,
    name,
    principal,
    interestRate,
    currency,
    paymentMethod,
    rateType,
    accountId,
    startDate,
    endDate,
    termMonths,
    monthlyPayment,
    statementDay,
    paymentDueDay,
    note,
    sync,
  );

  /// Create a copy of Liability
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LiabilityImplCopyWith<_$LiabilityImpl> get copyWith =>
      __$$LiabilityImplCopyWithImpl<_$LiabilityImpl>(this, _$identity);
}

abstract class _Liability implements Liability {
  const factory _Liability({
    required final String id,
    required final LiabilityType type,
    required final String name,
    required final Decimal principal,
    required final Decimal interestRate,
    required final String currency,
    final RepaymentMethod paymentMethod,
    final LiabilityRateType rateType,
    final String? accountId,
    final DateTime? startDate,
    final DateTime? endDate,
    final int? termMonths,
    final Decimal? monthlyPayment,
    final int? statementDay,
    final int? paymentDueDay,
    final String? note,
    required final SyncMeta sync,
  }) = _$LiabilityImpl;

  @override
  String get id;
  @override
  LiabilityType get type;
  @override
  String get name;
  @override
  Decimal get principal;

  /// Effective annual interest rate as a fraction (e.g. `0.0485` for
  /// 4.85%). For [LiabilityRateType.lprFloating] this is the rate at the
  /// time of last update; the UI should mark it as floating.
  @override
  Decimal get interestRate;
  @override
  String get currency;
  @override
  RepaymentMethod get paymentMethod;
  @override
  LiabilityRateType get rateType;
  @override
  String? get accountId;
  @override
  DateTime? get startDate;
  @override
  DateTime? get endDate;
  @override
  int? get termMonths;
  @override
  Decimal? get monthlyPayment;

  /// Day of month for credit-card statement closure (信用卡账单日). Used by
  /// the optional reminder feature; ignored for installment loans.
  @override
  int? get statementDay;

  /// Day of month for credit-card payment due (信用卡还款日).
  @override
  int? get paymentDueDay;
  @override
  String? get note;
  @override
  SyncMeta get sync;

  /// Create a copy of Liability
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LiabilityImplCopyWith<_$LiabilityImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
