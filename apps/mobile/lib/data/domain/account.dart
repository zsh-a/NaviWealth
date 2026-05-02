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

    /// FIR-126 — accounting classification of the account
    /// (asset / liability / income / expense / equity). Defaults to
    /// [AccountCategory.asset] for back-compat with code paths that still
    /// construct an [Account] without a category; UI / repo callers
    /// always supply an explicit value.
    @Default(AccountCategory.asset) AccountCategory category,
    required SyncMeta sync,
  }) = _Account;
}
