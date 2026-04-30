// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Asset {
  String get id => throw _privateConstructorUsedError;
  AssetType get type => throw _privateConstructorUsedError;
  String get symbol => throw _privateConstructorUsedError;
  String get currency => throw _privateConstructorUsedError;
  String? get name => throw _privateConstructorUsedError;
  String? get market => throw _privateConstructorUsedError;
  String? get industry => throw _privateConstructorUsedError;
  String? get region => throw _privateConstructorUsedError;
  String? get isin => throw _privateConstructorUsedError;
  Decimal? get lastPrice => throw _privateConstructorUsedError;
  DateTime? get lastPriceAt => throw _privateConstructorUsedError;
  String? get logoUrl => throw _privateConstructorUsedError;
  String? get metadataJson => throw _privateConstructorUsedError;
  SyncMeta get sync => throw _privateConstructorUsedError;

  /// Create a copy of Asset
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AssetCopyWith<Asset> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AssetCopyWith<$Res> {
  factory $AssetCopyWith(Asset value, $Res Function(Asset) then) =
      _$AssetCopyWithImpl<$Res, Asset>;
  @useResult
  $Res call({
    String id,
    AssetType type,
    String symbol,
    String currency,
    String? name,
    String? market,
    String? industry,
    String? region,
    String? isin,
    Decimal? lastPrice,
    DateTime? lastPriceAt,
    String? logoUrl,
    String? metadataJson,
    SyncMeta sync,
  });

  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class _$AssetCopyWithImpl<$Res, $Val extends Asset>
    implements $AssetCopyWith<$Res> {
  _$AssetCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Asset
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? symbol = null,
    Object? currency = null,
    Object? name = freezed,
    Object? market = freezed,
    Object? industry = freezed,
    Object? region = freezed,
    Object? isin = freezed,
    Object? lastPrice = freezed,
    Object? lastPriceAt = freezed,
    Object? logoUrl = freezed,
    Object? metadataJson = freezed,
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
                      as AssetType,
            symbol: null == symbol
                ? _value.symbol
                : symbol // ignore: cast_nullable_to_non_nullable
                      as String,
            currency: null == currency
                ? _value.currency
                : currency // ignore: cast_nullable_to_non_nullable
                      as String,
            name: freezed == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String?,
            market: freezed == market
                ? _value.market
                : market // ignore: cast_nullable_to_non_nullable
                      as String?,
            industry: freezed == industry
                ? _value.industry
                : industry // ignore: cast_nullable_to_non_nullable
                      as String?,
            region: freezed == region
                ? _value.region
                : region // ignore: cast_nullable_to_non_nullable
                      as String?,
            isin: freezed == isin
                ? _value.isin
                : isin // ignore: cast_nullable_to_non_nullable
                      as String?,
            lastPrice: freezed == lastPrice
                ? _value.lastPrice
                : lastPrice // ignore: cast_nullable_to_non_nullable
                      as Decimal?,
            lastPriceAt: freezed == lastPriceAt
                ? _value.lastPriceAt
                : lastPriceAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            logoUrl: freezed == logoUrl
                ? _value.logoUrl
                : logoUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            metadataJson: freezed == metadataJson
                ? _value.metadataJson
                : metadataJson // ignore: cast_nullable_to_non_nullable
                      as String?,
            sync: null == sync
                ? _value.sync
                : sync // ignore: cast_nullable_to_non_nullable
                      as SyncMeta,
          )
          as $Val,
    );
  }

  /// Create a copy of Asset
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
abstract class _$$AssetImplCopyWith<$Res> implements $AssetCopyWith<$Res> {
  factory _$$AssetImplCopyWith(
    _$AssetImpl value,
    $Res Function(_$AssetImpl) then,
  ) = __$$AssetImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    AssetType type,
    String symbol,
    String currency,
    String? name,
    String? market,
    String? industry,
    String? region,
    String? isin,
    Decimal? lastPrice,
    DateTime? lastPriceAt,
    String? logoUrl,
    String? metadataJson,
    SyncMeta sync,
  });

  @override
  $SyncMetaCopyWith<$Res> get sync;
}

/// @nodoc
class __$$AssetImplCopyWithImpl<$Res>
    extends _$AssetCopyWithImpl<$Res, _$AssetImpl>
    implements _$$AssetImplCopyWith<$Res> {
  __$$AssetImplCopyWithImpl(
    _$AssetImpl _value,
    $Res Function(_$AssetImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Asset
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? symbol = null,
    Object? currency = null,
    Object? name = freezed,
    Object? market = freezed,
    Object? industry = freezed,
    Object? region = freezed,
    Object? isin = freezed,
    Object? lastPrice = freezed,
    Object? lastPriceAt = freezed,
    Object? logoUrl = freezed,
    Object? metadataJson = freezed,
    Object? sync = null,
  }) {
    return _then(
      _$AssetImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as AssetType,
        symbol: null == symbol
            ? _value.symbol
            : symbol // ignore: cast_nullable_to_non_nullable
                  as String,
        currency: null == currency
            ? _value.currency
            : currency // ignore: cast_nullable_to_non_nullable
                  as String,
        name: freezed == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String?,
        market: freezed == market
            ? _value.market
            : market // ignore: cast_nullable_to_non_nullable
                  as String?,
        industry: freezed == industry
            ? _value.industry
            : industry // ignore: cast_nullable_to_non_nullable
                  as String?,
        region: freezed == region
            ? _value.region
            : region // ignore: cast_nullable_to_non_nullable
                  as String?,
        isin: freezed == isin
            ? _value.isin
            : isin // ignore: cast_nullable_to_non_nullable
                  as String?,
        lastPrice: freezed == lastPrice
            ? _value.lastPrice
            : lastPrice // ignore: cast_nullable_to_non_nullable
                  as Decimal?,
        lastPriceAt: freezed == lastPriceAt
            ? _value.lastPriceAt
            : lastPriceAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        logoUrl: freezed == logoUrl
            ? _value.logoUrl
            : logoUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        metadataJson: freezed == metadataJson
            ? _value.metadataJson
            : metadataJson // ignore: cast_nullable_to_non_nullable
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

class _$AssetImpl extends _Asset {
  const _$AssetImpl({
    required this.id,
    required this.type,
    required this.symbol,
    required this.currency,
    this.name,
    this.market,
    this.industry,
    this.region,
    this.isin,
    this.lastPrice,
    this.lastPriceAt,
    this.logoUrl,
    this.metadataJson,
    required this.sync,
  }) : super._();

  @override
  final String id;
  @override
  final AssetType type;
  @override
  final String symbol;
  @override
  final String currency;
  @override
  final String? name;
  @override
  final String? market;
  @override
  final String? industry;
  @override
  final String? region;
  @override
  final String? isin;
  @override
  final Decimal? lastPrice;
  @override
  final DateTime? lastPriceAt;
  @override
  final String? logoUrl;
  @override
  final String? metadataJson;
  @override
  final SyncMeta sync;

  @override
  String toString() {
    return 'Asset(id: $id, type: $type, symbol: $symbol, currency: $currency, name: $name, market: $market, industry: $industry, region: $region, isin: $isin, lastPrice: $lastPrice, lastPriceAt: $lastPriceAt, logoUrl: $logoUrl, metadataJson: $metadataJson, sync: $sync)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AssetImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.currency, currency) ||
                other.currency == currency) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.market, market) || other.market == market) &&
            (identical(other.industry, industry) ||
                other.industry == industry) &&
            (identical(other.region, region) || other.region == region) &&
            (identical(other.isin, isin) || other.isin == isin) &&
            (identical(other.lastPrice, lastPrice) ||
                other.lastPrice == lastPrice) &&
            (identical(other.lastPriceAt, lastPriceAt) ||
                other.lastPriceAt == lastPriceAt) &&
            (identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl) &&
            (identical(other.metadataJson, metadataJson) ||
                other.metadataJson == metadataJson) &&
            (identical(other.sync, sync) || other.sync == sync));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    type,
    symbol,
    currency,
    name,
    market,
    industry,
    region,
    isin,
    lastPrice,
    lastPriceAt,
    logoUrl,
    metadataJson,
    sync,
  );

  /// Create a copy of Asset
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AssetImplCopyWith<_$AssetImpl> get copyWith =>
      __$$AssetImplCopyWithImpl<_$AssetImpl>(this, _$identity);
}

abstract class _Asset extends Asset {
  const factory _Asset({
    required final String id,
    required final AssetType type,
    required final String symbol,
    required final String currency,
    final String? name,
    final String? market,
    final String? industry,
    final String? region,
    final String? isin,
    final Decimal? lastPrice,
    final DateTime? lastPriceAt,
    final String? logoUrl,
    final String? metadataJson,
    required final SyncMeta sync,
  }) = _$AssetImpl;
  const _Asset._() : super._();

  @override
  String get id;
  @override
  AssetType get type;
  @override
  String get symbol;
  @override
  String get currency;
  @override
  String? get name;
  @override
  String? get market;
  @override
  String? get industry;
  @override
  String? get region;
  @override
  String? get isin;
  @override
  Decimal? get lastPrice;
  @override
  DateTime? get lastPriceAt;
  @override
  String? get logoUrl;
  @override
  String? get metadataJson;
  @override
  SyncMeta get sync;

  /// Create a copy of Asset
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AssetImplCopyWith<_$AssetImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
