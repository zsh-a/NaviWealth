import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';

part 'category.freezed.dart';

/// Tree-structured taxonomy. Distinct from [Tag] in that a category has at
/// most one parent and can express hierarchical roll-ups (e.g.
/// `Tech > Semiconductors > Foundry`).
@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    required String name,
    String? parentId,
    int? sortOrder,
    required SyncMeta sync,
  }) = _Category;
}
