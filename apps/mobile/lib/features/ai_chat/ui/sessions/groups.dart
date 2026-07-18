part of 'sessions_panel.dart';

class _SessionGroup {
  const _SessionGroup({required this.label, required this.sessions});

  final String label;
  final List<ChatSession> sessions;
}

/// Bucket sessions for the history list:
///  1. Pinned (if any)
///  2. Recency buckets for non-archived, non-pinned threads
///  3. Archived (only when [includeArchived] is true)
///
/// Sessions arrive sorted pinned-first then newest-first from the store.
List<_SessionGroup> _groupSessions(
  List<ChatSession> sessions,
  DateTime now,
  AppLocalizations l10n, {
  required bool includeArchived,
}) {
  final pinned = <ChatSession>[];
  final active = <ChatSession>[];
  final archived = <ChatSession>[];
  for (final s in sessions) {
    if (s.archived) {
      if (includeArchived) archived.add(s);
      continue;
    }
    if (s.pinned) {
      pinned.add(s);
    } else {
      active.add(s);
    }
  }

  final out = <_SessionGroup>[];
  if (pinned.isNotEmpty) {
    out.add(
      _SessionGroup(label: l10n.aiChatSessionsGroupPinned, sessions: pinned),
    );
  }
  out.addAll(_groupByRecency(active, now, l10n));
  if (archived.isNotEmpty) {
    out.add(
      _SessionGroup(
        label: l10n.aiChatSessionsGroupArchived,
        sessions: archived,
      ),
    );
  }
  return out;
}

/// Bucket sessions by recency of their last message. Sessions arrive
/// sorted newest-first (per [chatSessionsStreamProvider]), so within
/// each bucket the order is preserved. Buckets are emitted only when
/// non-empty so a thread-light history collapses to a single section.
List<_SessionGroup> _groupByRecency(
  List<ChatSession> sessions,
  DateTime now,
  AppLocalizations l10n,
) {
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 7));
  final monthStart = today.subtract(const Duration(days: 30));

  final tToday = <ChatSession>[];
  final tYesterday = <ChatSession>[];
  final tWeek = <ChatSession>[];
  final tMonth = <ChatSession>[];
  final tOlder = <ChatSession>[];

  for (final s in sessions) {
    final ts = (s.lastMessageAt ?? s.createdAt).toLocal();
    final day = DateTime(ts.year, ts.month, ts.day);
    if (!day.isBefore(today)) {
      tToday.add(s);
    } else if (!day.isBefore(yesterday)) {
      tYesterday.add(s);
    } else if (!day.isBefore(weekStart)) {
      tWeek.add(s);
    } else if (!day.isBefore(monthStart)) {
      tMonth.add(s);
    } else {
      tOlder.add(s);
    }
  }

  final out = <_SessionGroup>[];
  if (tToday.isNotEmpty) {
    out.add(
      _SessionGroup(label: l10n.aiChatSessionsGroupToday, sessions: tToday),
    );
  }
  if (tYesterday.isNotEmpty) {
    out.add(
      _SessionGroup(
        label: l10n.aiChatSessionsGroupYesterday,
        sessions: tYesterday,
      ),
    );
  }
  if (tWeek.isNotEmpty) {
    out.add(
      _SessionGroup(label: l10n.aiChatSessionsGroupThisWeek, sessions: tWeek),
    );
  }
  if (tMonth.isNotEmpty) {
    out.add(
      _SessionGroup(label: l10n.aiChatSessionsGroupThisMonth, sessions: tMonth),
    );
  }
  if (tOlder.isNotEmpty) {
    out.add(
      _SessionGroup(label: l10n.aiChatSessionsGroupOlder, sessions: tOlder),
    );
  }
  return out;
}
