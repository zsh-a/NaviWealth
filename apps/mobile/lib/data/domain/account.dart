import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'account.freezed.dart';

@freezed
abstract class Account with _$Account {
  const factory Account({
    required String id,
    required AccountType type,
    required String name,
    required String currency,
    String? institution,
    String? accountNumber,
    String? note,
    @Default(false) bool archived,
    required SyncMeta sync,
  }) = _Account;
}
