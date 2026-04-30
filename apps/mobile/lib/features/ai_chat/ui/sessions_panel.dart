import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/providers.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';

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
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(authSessionReaderProvider)();

    if (session == null) {
      return _PanelShell(
        cs: cs,
        onNew: null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.s24),
            child: Text(
              '请先登录后再使用 AI 助手。',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final sessionsAsync = ref.watch(chatSessionsStreamProvider(session.userId));
    return _PanelShell(
      cs: cs,
      onNew: onNew,
      child: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Spacing.s16),
          child: Text(
            '加载失败：$e',
            style: tt.bodySmall?.copyWith(color: cs.error),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.s24),
                child: Text(
                  '点击右上角的 + 开始第一个对话。',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
            itemCount: sessions.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话？'),
        content: Text('"${session.title}" 中的所有消息都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
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
    final controller = TextEditingController(text: session.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == session.title) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.renameSession(session.id, result);
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.cs, required this.onNew, required this.child});

  final ColorScheme cs;
  final VoidCallback? onNew;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      color: cs.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.s16,
              Spacing.s12,
              Spacing.s8,
              Spacing.s8,
            ),
            child: Row(
              children: [
                Text(
                  '对话',
                  style: tt.titleMedium?.copyWith(color: cs.onSurface),
                ),
                const Spacer(),
                if (onNew != null)
                  IconButton(
                    tooltip: '新建对话',
                    onPressed: onNew,
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(child: child),
        ],
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
    final lastAt = session.lastMessageAt ?? session.createdAt;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        color: selected
                            ? cs.onSecondaryContainer
                            : cs.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      _formatRelative(lastAt),
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      onRename();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatRelative(DateTime when) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(when.toUtc());
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  final local = when.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}
