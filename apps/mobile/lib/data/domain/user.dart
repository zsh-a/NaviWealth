import 'package:freezed_annotation/freezed_annotation.dart';

import 'sync_meta.dart';

part 'user.freezed.dart';

@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String name,
    String? email,
    required DateTime createdAt,
    required SyncMeta sync,
  }) = _User;
}
