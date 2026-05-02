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

    /// FIR-130 — Beancount-style account tree. NULL on top-level
    /// accounts; on a child the parent's [id] forms the chain. The tree
    /// is enforced as a parent / child relationship at the application
    /// level (no DB constraint) so a sync-borne reorder doesn't fight
    /// foreign-key checks during eventual-consistency replay.
    String? parentId,

    /// FIR-130 — Material icon name driving the account's avatar in the
    /// picker / list. Lifted off the legacy `expense_categories.icon`
    /// surface so a single account-tree picker can render every category.
    String? icon,

    /// FIR-130 — colour token for the account's avatar (hex or design
    /// token id). Same provenance as [icon].
    String? color,
    required SyncMeta sync,
  }) = _Account;
}
