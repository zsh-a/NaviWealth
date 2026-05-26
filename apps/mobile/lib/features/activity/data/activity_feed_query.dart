import 'package:flutter/material.dart';

import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

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

  static ActivityFeedQuery fromUri(Uri uri) {
    final params = uri.queryParameters;
    final accounts = _csv(params['accounts']).toSet();
    final kinds = _csv(
      params['kinds'],
    ).map(activityKindFromWire).whereType<ActivityKind>().toSet();
    final from = _parseDate(params['from']);
    final to = _parseDate(params['to']);
    final dateRange = from == null && to == null
        ? null
        : DateTimeRange(
            start: from ?? DateTime.utc(1970),
            end: to ?? DateTime.utc(9999, 12, 31),
          );
    return ActivityFeedQuery(
      dateRange: dateRange,
      accountIds: accounts,
      kinds: kinds,
    );
  }

  Map<String, String> toQueryParameters() {
    final out = <String, String>{};
    if (accountIds.isNotEmpty) {
      out['accounts'] = (_sorted(accountIds)).join(',');
    }
    if (kinds.isNotEmpty) {
      out['kinds'] = (_sorted(kinds.map((k) => k.wire))).join(',');
    }
    final range = dateRange;
    if (range != null) {
      out['from'] = _dateOnly(range.start);
      out['to'] = _dateOnly(range.end);
    }
    return out;
  }
}

class ActivityFeedPage {
  const ActivityFeedPage({
    required this.entries,
    required this.totalCount,
    required this.hasMore,
    required this.isFiltered,
    required this.accountsById,
  });

  final List<JournalEntryWithPostings> entries;
  final int totalCount;
  final bool hasMore;
  final bool isFiltered;
  final Map<String, Account> accountsById;
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

EntryKind entryKindFromActivityKind(ActivityKind kind) {
  return switch (kind) {
    ActivityKind.expense => EntryKind.expense,
    ActivityKind.transfer => EntryKind.transfer,
    ActivityKind.trade => EntryKind.trade,
    ActivityKind.income => EntryKind.income,
    ActivityKind.payment => EntryKind.payment,
    ActivityKind.adjustment => EntryKind.adjustment,
    ActivityKind.opening => EntryKind.opening,
    ActivityKind.other => EntryKind.other,
  };
}

ActivityKind? activityKindFromWire(String wire) {
  for (final kind in ActivityKind.values) {
    if (kind.wire == wire) return kind;
  }
  return null;
}

extension ActivityKindWire on ActivityKind {
  String get wire => name;
}

List<String> _csv(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _dateOnly(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

List<String> _sorted(Iterable<String> values) {
  return values.toList(growable: false)..sort();
}
