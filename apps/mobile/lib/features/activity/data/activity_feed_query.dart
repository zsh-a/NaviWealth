import 'package:flutter/material.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/repositories/journal_entry_repository.dart';

enum ActivityKind {
  expense,
  transfer,
  trade,
  income,
  payment,
  adjustment,
  opening,
  other,
}

class ActivityFeedQuery {
  const ActivityFeedQuery({
    this.dateRange,
    this.accountIds = const <String>{},
    this.kinds = const <ActivityKind>{},
    this.pageSize = 50,
  });

  final DateTimeRange? dateRange;
  final Set<String> accountIds;
  final Set<ActivityKind> kinds;
  final int pageSize;

  bool get hasFilters =>
      dateRange != null || accountIds.isNotEmpty || kinds.isNotEmpty;

  ActivityFeedQuery copyWith({
    Object? dateRange = _sentinel,
    Set<String>? accountIds,
    Set<ActivityKind>? kinds,
    int? pageSize,
  }) {
    return ActivityFeedQuery(
      dateRange: dateRange == _sentinel
          ? this.dateRange
          : dateRange as DateTimeRange?,
      accountIds: accountIds ?? this.accountIds,
      kinds: kinds ?? this.kinds,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  static const Object _sentinel = Object();
}

class ActivityFeedPage {
  const ActivityFeedPage({
    required this.entries,
    required this.totalCount,
    required this.hasMore,
    required this.isFiltered,
  });

  final List<JournalEntryWithPostings> entries;
  final int totalCount;
  final bool hasMore;
  final bool isFiltered;
}

List<JournalEntryWithPostings> filterActivityEntries({
  required List<JournalEntryWithPostings> entries,
  required ActivityFeedQuery query,
  required Map<String, Account> accountsById,
}) {
  return entries
      .where((entry) {
        final dateRange = query.dateRange;
        if (dateRange != null) {
          final date = entry.entry.date;
          if (date.isBefore(dateRange.start) || !date.isBefore(dateRange.end)) {
            return false;
          }
        }

        if (query.accountIds.isNotEmpty) {
          final touchesAccount = entry.postings.any(
            (posting) => query.accountIds.contains(posting.accountId),
          );
          if (!touchesAccount) return false;
        }

        if (query.kinds.isNotEmpty) {
          final classification = classifyEntryKind(
            postings: entry.postings,
            resolveCategory: (id) => accountsById[id]?.category,
          );
          if (!query.kinds.contains(
            _activityKindFromEntryKind(classification.kind),
          )) {
            return false;
          }
        }

        return true;
      })
      .toList(growable: false);
}

ActivityKind _activityKindFromEntryKind(EntryKind kind) {
  return switch (kind) {
    EntryKind.expense => ActivityKind.expense,
    EntryKind.transfer => ActivityKind.transfer,
    EntryKind.trade => ActivityKind.trade,
    EntryKind.income => ActivityKind.income,
    EntryKind.payment => ActivityKind.payment,
    EntryKind.adjustment => ActivityKind.adjustment,
    EntryKind.opening => ActivityKind.opening,
    EntryKind.other => ActivityKind.other,
  };
}
