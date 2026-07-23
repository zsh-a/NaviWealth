import 'package:flutter/foundation.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

/// User-facing FinanceOS spending category.
///
/// Categories own presentation and planning identity. [ledgerAccountId] is a
/// hidden bridge into the double-entry ledger and must never be exposed as the
/// category id in UI, budgets, AI contracts, or report aggregation.
@immutable
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.nameOverride,
    this.systemKey,
    this.parentId,
    required this.ledgerAccountId,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.archived = false,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String name;
  final String? nameOverride;
  final String? systemKey;
  final String? parentId;
  final String ledgerAccountId;
  final String? icon;
  final String? color;
  final int sortOrder;
  final bool archived;
  final String? mergedIntoId;
  final SyncMeta sync;

  bool get isBuiltIn => systemKey != null;
  bool get isMerged => mergedIntoId != null;
}
