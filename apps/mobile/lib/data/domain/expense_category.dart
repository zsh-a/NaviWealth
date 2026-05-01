import 'package:freezed_annotation/freezed_annotation.dart';

import 'sync_meta.dart';

part 'expense_category.freezed.dart';

/// FIR-68 — taxonomy node for [Expense] rows.
///
/// Two-level tree: a row with a non-null [parentId] is a sub-category. Icon
/// and color are presentation-only hints carried alongside the row so peers
/// see the same visual without each device shipping its own theme.
///
/// [archivedAt] is a *user-archive* signal (the row is hidden from the
/// default picker but still resolvable by id) and is orthogonal to the
/// [SyncMeta.deletedAt] tombstone — archived rows still sync and can be
/// restored by clearing [archivedAt]; tombstoned rows are gone.
@freezed
abstract class ExpenseCategory with _$ExpenseCategory {
  const factory ExpenseCategory({
    required String id,
    required String name,
    String? parentId,
    String? icon,
    String? color,
    int? sortOrder,
    DateTime? archivedAt,
    required SyncMeta sync,
  }) = _ExpenseCategory;
}
