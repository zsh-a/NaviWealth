import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import 'shadcn/s_primitives.dart';

/// List of past chat sessions. Used as a permanent sidebar on
/// tablet/desktop, and shown inside a [Drawer] on mobile.
///
/// Renders an empty-state cell when the user has never chatted, plus a
/// "+" affordance the surrounding page handles by opening a brand-new
/// session.
class SessionsPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authSessionProvider);

    if (session == null) {
      return _PanelShell(
        cs: cs,
        onNew: null,
        child: _PanelMessage(
          icon: Icons.lock_outline,
          message: l10n.aiChatLoginRequired,
        ),
      );
    }

    final sessionsAsync = ref.watch(chatSessionsStreamProvider(session.userId));
    return _PanelShell(
      cs: cs,
      onNew: onNew,
      child: sessionsAsync.when(
        loading: () => const Center(
          child: SizedBox(width: 24, height: 24, child: FCircularProgress()),
        ),
        error: (e, _) => _PanelMessage(
          icon: Icons.error_outline,
          iconColor: cs.error,
          message: l10n.commonLoadError(e.toString()),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _PanelMessage(
              icon: Icons.chat_bubble_outline,
              message: l10n.aiChatSessionsEmpty,
              action: SButton(
                variant: SButtonVariant.primary,
                onPressed: onNew,
                icon: Icons.add,
                label: l10n.aiChatNewSessionTooltip,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final s = sessions[i];
              final selected = s.id == activeSessionId;
              return _SessionTile(
                session: s,
                selected: selected,
                onTap: () => onSelect(s.id),
                onDelete: () => _confirmDelete(context, ref, s),
                onRename: () => _promptRename(context, ref, s),
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
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiChatSessionDeleteTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.aiChatSessionDeleteBody(session.title)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SButton(
                  variant: SButtonVariant.ghost,
                  onPressed: () => Navigator.of(ctx).pop(false),
                  label: l10n.commonCancel,
                ),
                const SizedBox(width: 8),
                SButton(
                  variant: SButtonVariant.outline,
                  onPressed: () => Navigator.of(ctx).pop(true),
                  label: l10n.commonDelete,
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
          ],
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
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final padding = MediaQuery.viewInsetsOf(ctx).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: padding + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.aiChatSessionRenameTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: l10n.aiChatSessionTitleLabel,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SButton(
                      variant: SButtonVariant.ghost,
                      onPressed: () => Navigator.of(ctx).pop(),
                      label: l10n.commonCancel,
                    ),
                    const SizedBox(width: 8),
                    SButton(
                      variant: SButtonVariant.primary,
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                      label: l10n.commonSave,
                    ),
                  ],
                ),
              ],
            ),
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
  const _PanelShell({
    required this.cs,
    required this.onNew,
    required this.child,
  });

  final ColorScheme cs;
  final VoidCallback? onNew;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: cs.surface,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    l10n.aiChatSessionsHeader,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (onNew != null)
                    IconButton(
                      tooltip: l10n.aiChatNewSessionTooltip,
                      onPressed: onNew,
                      icon: const Icon(Icons.add),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        foregroundColor: cs.onPrimaryContainer,
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: iconColor ?? cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final lastAt = session.lastMessageAt ?? session.createdAt;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? cs.primary : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: selected ? cs.primary : cs.onSurfaceVariant,
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
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatRelative(l10n, lastAt),
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.aiChatSessionMoreTooltip,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: () => _showActions(context, l10n, cs),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionRow(
                icon: Icons.edit_outlined,
                label: l10n.aiChatSessionRenameAction,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onRename();
                },
              ),
              const SizedBox(height: 4),
              _ActionRow(
                icon: Icons.delete_outline,
                label: l10n.commonDelete,
                color: cs.error,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete();
                },
              ),
            ],
          ),
        ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = color ?? cs.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Text(label, style: tt.bodyLarge?.copyWith(color: fg)),
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
