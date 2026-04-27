// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Transaction {
  String get id => throw _privateConstructorUsedError;
  String get accountId => throw _privateConstructorUsedError;
  String? get assetId => throw _privateConstructorUsedError;
  TransactionType get type => throw _privateConstructorUsedError;
  Decimal get quantity => throw _privateConstructorUsedError;
  Decimal get price => throw _privateConstructorUsedError;
  String get currency => throw _privateConstructorUsedError;
  DateTime get tradeDate => throw _privateConstructorUsedError;
  DateTime? get settleDate => throw _privateConstructorUsedError;
  Decimal? get fee => throw _privateConstructorUsedError;
  Decimal? get tax => throw _privateConstructorUsedError;
  String? get counterAccountId => throw _privateConstructorUsedError;
  String? get lotId => throw _privateConstructorUsedError;
  String? get note => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Transaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TransactionCopyWith<Transaction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransactionCopyWith<$Res> {
  factory $TransactionCopyWith(
    Transaction value,
    $Res Function(Transaction) then,
  ) = _$TransactionCopyWithImpl<$Res, Transaction>;
  @useResult
  $Res call({
    String id,
    String accountId,
    String? assetId,
    TransactionType type,
    Decimal quantity,
    Decimal price,
    String currency,
    DateTime tradeDate,
    DateTime? settleDate,
    Decimal? fee,
    Decimal? tax,
    String? counterAccountId,
    String? lotId,
    String? note,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$TransactionCopyWithImpl<$Res, $Val extends Transaction>
    implements $TransactionCopyWith<$Res> {
  _$TransactionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Transaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? accountId = null,
    Object? assetId = freezed,
    Object? type = null,
    Object? quantity = null,
    Object? price = null,
    Object? currency = null,
    Object? tradeDate = null,
    Object? settleDate = freezed,
    Object? fee = freezed,
    Object? tax = freezed,
    Object? counterAccountId = freezed,
    Object? lotId = freezed,
    Object? note = freezed,
    Object? sync = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            accountId: null == accountId
                ? _value.accountId
                : accountId // ignore: cast_nullable_to_non_nullable
                      as String,
            assetId: freezed == assetId
                ? _value.assetId
                : assetId // ignore: cast_nullable_to_non_nullable
                      as String?,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as TransactionType,
            quantity: null == quantity
                ? _value.quantity
                : quantity // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            price: null == price
                ? _value.price
                : price // ignore: cast_nullable_to_non_nullable
                      as Decimal,
            currency: null == currency
                ? _value.currency
                : currency // ignore: cast_nullable_to_non_nullable
                      as String,
            tradeDate: null == tradeDate
                ? _value.tradeDate
                : tradeDate // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            settleDate: freezed == settleDate
                ? _value.settleDate
                : settleDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            fee: freezed == fee
                ? _value.fee
                : fee // ignore: cast_nullable_to_non_nullable
                      as Decimal?,
            tax: freezed == tax
                ? _value.tax
                : tax // ignore: cast_nullable_to_non_nullable
                      as Decimal?,
            counterAccountId: freezed == counterAccountId
                ? _value.counterAccountId
                : counterAccountId // ignore: cast_nullable_to_non_nullable
                      as String?,
            lotId: freezed == lotId
                ? _value.lotId
                : lotId // ignore: cast_nullable_to_non_nullable
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

  /// Create a copy of Transaction
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
abstract class _$$TransactionImplCopyWith<$Res>
    implements $TransactionCopyWith<$Res> {
  factory _$$TransactionImplCopyWith(
    _$TransactionImpl value,
    $Res Function(_$TransactionImpl) then,
  ) = __$$TransactionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String accountId,
    String? assetId,
    TransactionType type,
    Decimal quantity,
    Decimal price,
    String currency,
    DateTime tradeDate,
    DateTime? settleDate,
    Decimal? fee,
    Decimal? tax,
    String? counterAccountId,
    String? lotId,
    String? note,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$TransactionImplCopyWithImpl<$Res>
    extends _$TransactionCopyWithImpl<$Res, _$TransactionImpl>
    implements _$$TransactionImplCopyWith<$Res> {
  __$$TransactionImplCopyWithImpl(
    _$TransactionImpl _value,
    $Res Function(_$TransactionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Transaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? accountId = null,
    Object? assetId = freezed,
    Object? type = null,
    Object? quantity = null,
    Object? price = null,
    Object? currency = null,
    Object? tradeDate = null,
    Object? settleDate = freezed,
    Object? fee = freezed,
    Object? tax = freezed,
    Object? counterAccountId = freezed,
    Object? lotId = freezed,
    Object? note = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$TransactionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        accountId: null == accountId
            ? _value.accountId
            : accountId // ignore: cast_nullable_to_non_nullable
                  as String,
        assetId: freezed == assetId
            ? _value.assetId
            : assetId // ignore: cast_nullable_to_non_nullable
                  as String?,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as TransactionType,
        quantity: null == quantity
            ? _value.quantity
            : quantity // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        price: null == price
            ? _value.price
            : price // ignore: cast_nullable_to_non_nullable
                  as Decimal,
        currency: null == currency
            ? _value.currency
            : currency // ignore: cast_nullable_to_non_nullable
                  as String,
        tradeDate: null == tradeDate
            ? _value.tradeDate
            : tradeDate // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        settleDate: freezed == settleDate
            ? _value.settleDate
            : settleDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        fee: freezed == fee
            ? _value.fee
            : fee // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        tax: freezed == tax
            ? _value.tax
            : tax // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        counterAccountId: freezed == counterAccountId
            ? _value.counterAccountId
            : counterAccountId // ignore: cast_nullable_to_non_nullable
                  as String?,
        lotId: freezed == lotId
            ? _value.lotId
            : lotId // ignore: cast_nullable_to_non_nullable
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

class _$TransactionImpl implements _Transaction {
  const _$TransactionImpl({
    required this.id,
    required this.accountId,
    this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.tradeDate,
    this.settleDate,
    this.fee,
    this.tax,
    this.counterAccountId,
    this.lotId,
    this.note,
    required this.sync,
  });

  @override
  final String id;
  @override
  final String accountId;
  @override
  final String? assetId;
  @override
  final TransactionType type;
  @override
  final Decimal quantity;
  @override
  final Decimal price;
  @override
  final String currency;
  @override
  final DateTime tradeDate;
  @override
  final DateTime? settleDate;
  @override
  final Decimal? fee;
  @override
  final Decimal? tax;
  @override
  final String? counterAccountId;
  @override
  final String? lotId;
  @override
  final String? note;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Transaction(id: $id, accountId: $accountId, assetId: $assetId, type: $type, quantity: $quantity, price: $price, currency: $currency, tradeDate: $tradeDate, settleDate: $settleDate, fee: $fee, tax: $tax, counterAccountId: $counterAccountId, lotId: $lotId, note: $note, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransactionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.accountId, accountId) ||
                other.accountId == accountId) &&
            (identical(other.assetId, assetId) || other.assetId == assetId) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity) &&
            (identical(other.price, price) || other.price == price) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            (identical(other.tradeDate, tradeDate) ||
                other.tradeDate == tradeDate) &&
            (identical(other.settleDate, settleDate) ||
                other.settleDate == settleDate) &&
            (identical(other.fee, fee) || other.fee == fee) &&
            (identical(other.tax, tax) || other.tax == tax) &&
            (identical(other.counterAccountId, counterAccountId) ||
                other.counterAccountId == counterAccountId) &&
            (identical(other.lotId, lotId) || other.lotId == lotId) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    accountId,
    assetId,
    type,
    quantity,
    price,
    currency,
    tradeDate,
    settleDate,
    fee,
    tax,
    counterAccountId,
    lotId,
    note,
    sync,
  );

  /// Create a copy of Transaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TransactionImplCopyWith<_$TransactionImpl> get copyWith =>
      __$$TransactionImplCopyWithImpl<_$TransactionImpl>(this, _$identity);
}

abstract class _Transaction implements Transaction {
  const factory _Transaction({
    required final String id,
    required final String accountId,
    final String? assetId,
    required final TransactionType type,
    required final Decimal quantity,
    required final Decimal price,
    required final String currency,
    required final DateTime tradeDate,
    final DateTime? settleDate,
    final Decimal? fee,
    final Decimal? tax,
    final String? counterAccountId,
    final String? lotId,
    final String? note,
    required final SyncMeta sync,
  }) = _$TransactionImpl;

  @override
  String get id;
  @override
  String get accountId;
  @override
  String? get assetId;
  @override
  TransactionType get type;
  @override
  Decimal get quantity;
  @override
  Decimal get price;
  @override
  String get currency;
  @override
  DateTime get tradeDate;
  @override
  DateTime? get settleDate;
  @override
  Decimal? get fee;
  @override
  Decimal? get tax;
  @override
  String? get counterAccountId;
  @override
  String? get lotId;
  @override
  String? get note;
  @override
  SyncMeta get sync;

  /// Create a copy of Transaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TransactionImplCopyWith<_$TransactionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
