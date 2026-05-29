import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/current_user.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';

/// List of past chat sessions. Used as a permanent sidebar on
/// tablet/desktop, and as a right-slide [showFSheet] panel on mobile.
///
/// Renders an empty-state cell when the user has never chatted, plus a
/// "+" affordance the surrounding page handles by opening a brand-new
/// session. Sessions are grouped by recency (Today / Yesterday / This
/// week / This month / Older) and filterable through an inline search
/// box that appears once there's something to filter.
class SessionsPanel extends ConsumerStatefulWidget {
  const SessionsPanel({
    super.key,
    required this.activeSessionId,
    required this.onSelect,
    required this.onNew,
  });

  final String? activeSessionId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  @override
  ConsumerState<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends ConsumerState<SessionsPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Device-only AI is account-less; scope sessions by the active user id
    // ([kLocalOnlyUserId] in local-only mode). `null` only before auth settles.
    final userId = ref.watch(activeUserIdProvider);

    if (userId == null) {
      return _PanelShell(
        onNew: null,
        child: _PanelMessage(
          icon: FLucideIcons.lock,
          message: l10n.aiChatLoginRequired,
        ),
      );
    }

    final sessionsAsync = ref.watch(chatSessionsStreamProvider(userId));
    return _PanelShell(
      onNew: widget.onNew,
      // Surface the search box once there's at least one session — for
      // a single thread the affordance is just noise.
      searchBar: sessionsAsync.maybeWhen(
        data: (s) => s.isEmpty
            ? null
            : _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
        orElse: () => null,
      ),
      child: sessionsAsync.when(
        loading: () => const Center(
          child: SizedBox(width: 24, height: 24, child: FCircularProgress()),
        ),
        error: (e, _) => _PanelMessage(
          icon: FLucideIcons.circleAlert,
          iconColor: context.theme.colors.destructive,
          message: l10n.commonLoadError(e.toString()),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _PanelMessage(
              icon: FLucideIcons.messageCircle,
              message: l10n.aiChatSessionsEmpty,
              action: FButton(
                variant: FButtonVariant.primary,
                onPress: widget.onNew,
                prefix: const Icon(FLucideIcons.plus, size: 14),
                child: Text(l10n.aiChatNewSessionTooltip),
              ),
            );
          }
          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? sessions
              : sessions
                    .where((s) => s.title.toLowerCase().contains(query))
                    .toList(growable: false);
          if (filtered.isEmpty) {
            return _PanelMessage(
              icon: FLucideIcons.searchX,
              message: l10n.aiChatSessionsSearchEmpty(_query),
            );
          }
          final now = DateTime.now();
          final groups = _groupByRecency(filtered, now, l10n);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (i > 0) const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Text(
                      group.label,
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.mutedForeground,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final s in group.sessions) ...[
                    _SessionTile(
                      session: s,
                      selected: s.id == widget.activeSessionId,
                      onTap: () => widget.onSelect(s.id),
                      onDelete: () => _confirmDelete(context, ref, s),
                      onRename: () => _promptRename(context, ref, s),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ChatSession session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showAppFormSheet<bool>(
      context: context,
      builder: (ctx) => AppSheet(
        title: l10n.aiChatSessionDeleteTitle,
        footer: AppSheetFooter(
          submitLabel: l10n.commonDelete,
          cancelLabel: l10n.commonCancel,
          destructive: true,
          onSubmit: () => Navigator.of(ctx).pop(true),
        ),
        child: Text(
          l10n.aiChatSessionDeleteBody(session.title),
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.mutedForeground,
            height: 1.4,
          ),
        ),
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.deleteSession(session.id);
  }

  Future<void> _promptRename(
    BuildContext context,
    WidgetRef ref,
    ChatSession session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: session.title);
    final result = await showGuardedFormSheet<String>(
      context: context,
      builder: (ctx, dirty) {
        // Idempotent — bindTextControllers no-ops after the first call.
        dirty.bindTextControllers([controller]);
        return AppSheet(
          title: l10n.aiChatSessionRenameTitle,
          footer: AppSheetFooter(
            submitLabel: l10n.commonSave,
            cancelLabel: l10n.commonCancel,
            onSubmit: () {
              dirty.markPristine();
              Navigator.of(ctx).pop(controller.text.trim());
            },
          ),
          child: FTextField(
            control: FTextFieldControl.managed(controller: controller),
            autofocus: true,
            maxLength: 60,
            label: Text(l10n.aiChatSessionTitleLabel),
          ),
        );
      },
    );
    if (result == null || result.isEmpty || result == session.title) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.renameSession(session.id, result);
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.onNew, required this.child, this.searchBar});

  final VoidCallback? onNew;
  final Widget child;

  /// Optional inline search box rendered between the header and the
  /// list. `null` collapses the section entirely so panels that never
  /// have anything to filter (login-required, error states) don't show
  /// a useless input.
  final Widget? searchBar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return ColoredBox(
      color: colors.background,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                  child: Row(
                    children: [
                      Icon(
                        FLucideIcons.history,
                        size: 18,
                        color: colors.mutedForeground,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiChatSessionsHeader,
                        style: context.theme.typography.md.copyWith(
                          color: colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (onNew != null)
                        FTooltip(
                          tipBuilder: (_, _) =>
                              Text(l10n.aiChatNewSessionTooltip),
                          child: FButton.icon(
                            variant: FButtonVariant.secondary,
                            onPress: onNew,
                            child: const Icon(FLucideIcons.plus, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
                if (searchBar != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: searchBar!,
                  ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextField(
      control: FTextFieldControl.managed(
        controller: controller,
        // FTextFieldControl.managed passes a TextEditingValue, but for
        // search we only care about the string — unwrap here so callers
        // keep the cleaner ValueChanged<String> shape.
        onChange: (v) => onChanged(v.text),
      ),
      hint: l10n.aiChatSessionsSearchHint,
      maxLines: 1,
      keyboardType: TextInputType.text,
    );
  }
}

class _SessionGroup {
  const _SessionGroup({required this.label, required this.sessions});

  final String label;
  final List<ChatSession> sessions;
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

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.message,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final String message;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: iconColor ?? colors.mutedForeground),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final lastAt = session.lastMessageAt ?? session.createdAt;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ColoredBox(
        color: selected
            ? colors.primary.withValues(alpha: 0.10)
            : const Color(0x00000000),
        child: FTappable(
          onPress: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : const Color(0x00000000),
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  FLucideIcons.messageCircle,
                  size: 18,
                  color: selected ? colors.primary : colors.mutedForeground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.sm.copyWith(
                          color: colors.foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatRelative(l10n, lastAt),
                        style: context.theme.typography.xs2.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                FTooltip(
                  tipBuilder: (_, _) => Text(l10n.aiChatSessionMoreTooltip),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => _showActions(context, l10n),
                    child: Icon(
                      FLucideIcons.ellipsis,
                      size: 18,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, AppLocalizations l10n) {
    return showAppSheet<void>(
      context: context,
      title: l10n.aiChatSessionActionsTitle,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionRow(
            icon: FLucideIcons.pencil,
            label: l10n.aiChatSessionRenameAction,
            onTap: () {
              Navigator.of(ctx).pop();
              onRename();
            },
          ),
          const SizedBox(height: 4),
          _ActionRow(
            icon: FLucideIcons.trash2,
            label: l10n.commonDelete,
            color: ctx.theme.colors.destructive,
            onTap: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.theme.colors.foreground;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Text(
                label,
                style: context.theme.typography.md.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatRelative(AppLocalizations l10n, DateTime when) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(when.toUtc());
  if (diff.inMinutes < 1) return l10n.aiChatRelativeJustNow;
  if (diff.inHours < 1) return l10n.aiChatRelativeMinutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.aiChatRelativeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.aiChatRelativeDaysAgo(diff.inDays);
  final local = when.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}
