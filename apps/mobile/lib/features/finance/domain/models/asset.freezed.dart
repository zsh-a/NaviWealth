// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Asset {

 String get id; AssetType get type; String get symbol; String get currency; String? get name; String? get market; String? get industry; String? get region; String? get isin; String? get logoUrl; String? get metadataJson; SyncMeta get sync;
/// Create a copy of Asset
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssetCopyWith<Asset> get copyWith => _$AssetCopyWithImpl<Asset>(this as Asset, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Asset&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.symbol, symbol) || other.symbol == symbol)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.name, name) || other.name == name)&&(identical(other.market, market) || other.market == market)&&(identical(other.industry, industry) || other.industry == industry)&&(identical(other.region, region) || other.region == region)&&(identical(other.isin, isin) || other.isin == isin)&&(identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl)&&(identical(other.metadataJson, metadataJson) || other.metadataJson == metadataJson)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,symbol,currency,name,market,industry,region,isin,logoUrl,metadataJson,sync);

@override
String toString() {
  return 'Asset(id: $id, type: $type, symbol: $symbol, currency: $currency, name: $name, market: $market, industry: $industry, region: $region, isin: $isin, logoUrl: $logoUrl, metadataJson: $metadataJson, sync: $sync)';
}


}

/// @nodoc
abstract mixin class $AssetCopyWith<$Res>  {
  factory $AssetCopyWith(Asset value, $Res Function(Asset) _then) = _$AssetCopyWithImpl;
@useResult
$Res call({
 String id, AssetType type, String symbol, String currency, String? name, String? market, String? industry, String? region, String? isin, String? logoUrl, String? metadataJson, SyncMeta sync
});


$SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class _$AssetCopyWithImpl<$Res>
    implements $AssetCopyWith<$Res> {
  _$AssetCopyWithImpl(this._self, this._then);

  final Asset _self;
  final $Res Function(Asset) _then;

/// Create a copy of Asset
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? symbol = null,Object? currency = null,Object? name = freezed,Object? market = freezed,Object? industry = freezed,Object? region = freezed,Object? isin = freezed,Object? logoUrl = freezed,Object? metadataJson = freezed,Object? sync = null,}) {
  return _then(Asset(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AssetType,symbol: null == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,market: freezed == market ? _self.market : market // ignore: cast_nullable_to_non_nullable
as String?,industry: freezed == industry ? _self.industry : industry // ignore: cast_nullable_to_non_nullable
as String?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String?,isin: freezed == isin ? _self.isin : isin // ignore: cast_nullable_to_non_nullable
as String?,logoUrl: freezed == logoUrl ? _self.logoUrl : logoUrl // ignore: cast_nullable_to_non_nullable
as String?,metadataJson: freezed == metadataJson ? _self.metadataJson : metadataJson // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}
/// Create a copy of Asset
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SyncMetaCopyWith<$Res> get sync {
  
  return $SyncMetaCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [Asset].
extension AssetPatterns on Asset {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Asset value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Asset() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Asset value)  $default,){
final _that = this;
switch (_that) {
case _Asset():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Asset value)?  $default,){
final _that = this;
switch (_that) {
case _Asset() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  AssetType type,  String symbol,  String currency,  String? name,  String? market,  String? industry,  String? region,  String? isin,  String? logoUrl,  String? metadataJson,  SyncMeta sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Asset() when $default != null:
return $default(_that.id,_that.type,_that.symbol,_that.currency,_that.name,_that.market,_that.industry,_that.region,_that.isin,_that.logoUrl,_that.metadataJson,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  AssetType type,  String symbol,  String currency,  String? name,  String? market,  String? industry,  String? region,  String? isin,  String? logoUrl,  String? metadataJson,  SyncMeta sync)  $default,) {final _that = this;
switch (_that) {
case _Asset():
return $default(_that.id,_that.type,_that.symbol,_that.currency,_that.name,_that.market,_that.industry,_that.region,_that.isin,_that.logoUrl,_that.metadataJson,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  AssetType type,  String symbol,  String currency,  String? name,  String? market,  String? industry,  String? region,  String? isin,  String? logoUrl,  String? metadataJson,  SyncMeta sync)?  $default,) {final _that = this;
switch (_that) {
case _Asset() when $default != null:
return $default(_that.id,_that.type,_that.symbol,_that.currency,_that.name,_that.market,_that.industry,_that.region,_that.isin,_that.logoUrl,_that.metadataJson,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _Asset extends Asset {
  const _Asset({required this.id, required this.type, required this.symbol, required this.currency, this.name, this.market, this.industry, this.region, this.isin, this.logoUrl, this.metadataJson, required this.sync}): super._();
  

@override final  String id;
@override final  AssetType type;
@override final  String symbol;
@override final  String currency;
@override final  String? name;
@override final  String? market;
@override final  String? industry;
@override final  String? region;
@override final  String? isin;
@override final  String? logoUrl;
@override final  String? metadataJson;
@override final  SyncMeta sync;

/// Create a copy of Asset
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssetCopyWith<_Asset> get copyWith => __$AssetCopyWithImpl<_Asset>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Asset&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.symbol, symbol) || other.symbol == symbol)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.name, name) || other.name == name)&&(identical(other.market, market) || other.market == market)&&(identical(other.industry, industry) || other.industry == industry)&&(identical(other.region, region) || other.region == region)&&(identical(other.isin, isin) || other.isin == isin)&&(identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl)&&(identical(other.metadataJson, metadataJson) || other.metadataJson == metadataJson)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode => Object.hash(runtimeType,id,type,symbol,currency,name,market,industry,region,isin,logoUrl,metadataJson,sync);

@override
String toString() {
  return 'Asset(id: $id, type: $type, symbol: $symbol, currency: $currency, name: $name, market: $market, industry: $industry, region: $region, isin: $isin, logoUrl: $logoUrl, metadataJson: $metadataJson, sync: $sync)';
}


}

/// @nodoc
abstract mixin class _$AssetCopyWith<$Res> implements $AssetCopyWith<$Res> {
  factory _$AssetCopyWith(_Asset value, $Res Function(_Asset) _then) = __$AssetCopyWithImpl;
@override @useResult
$Res call({
 String id, AssetType type, String symbol, String currency, String? name, String? market, String? industry, String? region, String? isin, String? logoUrl, String? metadataJson, SyncMeta sync
});


@override $SyncMetaCopyWith<$Res> get sync;

}
/// @nodoc
class __$AssetCopyWithImpl<$Res>
    implements _$AssetCopyWith<$Res> {
  __$AssetCopyWithImpl(this._self, this._then);

  final _Asset _self;
  final $Res Function(_Asset) _then;

/// Create a copy of Asset
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? symbol = null,Object? currency = null,Object? name = freezed,Object? market = freezed,Object? industry = freezed,Object? region = freezed,Object? isin = freezed,Object? logoUrl = freezed,Object? metadataJson = freezed,Object? sync = null,}) {
  return _then(_Asset(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AssetType,symbol: null == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,market: freezed == market ? _self.market : market // ignore: cast_nullable_to_non_nullable
as String?,industry: freezed == industry ? _self.industry : industry // ignore: cast_nullable_to_non_nullable
as String?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as String?,isin: freezed == isin ? _self.isin : isin // ignore: cast_nullable_to_non_nullable
as String?,logoUrl: freezed == logoUrl ? _self.logoUrl : logoUrl // ignore: cast_nullable_to_non_nullable
as String?,metadataJson: freezed == metadataJson ? _self.metadataJson : metadataJson // ignore: cast_nullable_to_non_nullable
as String?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as SyncMeta,
  ));
}

/// Create a copy of Asset
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
