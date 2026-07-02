import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import 'enums.dart';

part 'tag.freezed.dart';

@freezed
abstract class Tag with _$Tag {
  const factory Tag({
    required String id,
    required String name,
    required TagKind kind,
    String? color,
    required SyncMeta sync,
  }) = _Tag;
}

/// M:N link between a [Tag] and the entity it labels (typically an [Asset]
/// or [Account], but we keep the entity table textual for forward
/// flexibility).
@freezed
abstract class TagLink with _$TagLink {
  const factory TagLink({
    required String id,
    required String tagId,
    required String entityTable,
    required String entityId,
    required SyncMeta sync,
  }) = _TagLink;
}
