import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'asset.freezed.dart';

@freezed
class Asset with _$Asset {
  const factory Asset({
    required String id,
    required AssetType type,
    required String symbol,
    required String currency,
    String? name,
    String? market,
    String? industry,
    String? region,
    String? isin,
    Decimal? lastPrice,
    DateTime? lastPriceAt,
    String? logoUrl,
    String? metadataJson,
    required SyncMeta sync,
  }) = _Asset;
}
