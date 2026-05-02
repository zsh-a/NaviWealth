import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/domain/expense_category.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import 'expense_category_visuals.dart';

/// CRUD surface for expense categories. Active rows render at the top with
/// drag handles for reorder; archived rows fall to the bottom in a muted
/// state with a single "unarchive" affordance.
class ExpenseCategoriesPage extends ConsumerWidget {
  const ExpenseCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allExpenseCategoriesStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('支出类目')),
      body: all.when(
        data: (cats) => _CategoryList(categories: cats),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: AppFab.extended(
        onPressed: () => _showEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('新建类目'),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories});

  final List<ExpenseCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = categories.where((c) => c.archivedAt == null).toList();
    final archived = categories.where((c) => c.archivedAt != null).toList();

    return ReorderableListView(
      padding: Spacing.pageMobile,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) async {
        if (oldIndex < newIndex) newIndex -= 1;
        if (newIndex >= active.length) newIndex = active.length - 1;
        if (oldIndex == newIndex) return;
        final reordered = [...active];
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        final repo = await ref.read(expenseCategoryRepositoryProvider.future);
        for (var i = 0; i < reordered.length; i++) {
          if (reordered[i].sortOrder != i) {
            await repo.update(reordered[i].id, sortOrder: i);
          }
        }
      },
      children: [
        for (var i = 0; i < active.length; i++)
          _CategoryTile(
            key: ValueKey(active[i].id),
            category: active[i],
            index: i,
            onEdit: () => _showEditor(context, ref, active[i]),
            onArchive: () async {
              final repo = await ref.read(
                expenseCategoryRepositoryProvider.future,
              );
              await repo.archive(active[i].id);
            },
          ),
        if (archived.isNotEmpty)
          Padding(
            key: const ValueKey('__archived_header'),
            padding: const EdgeInsets.only(
              top: Spacing.s24,
              bottom: Spacing.s8,
            ),
            child: Text(
              '已归档',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        for (final cat in archived)
          _ArchivedTile(
            key: ValueKey('arch-${cat.id}'),
            category: cat,
            onUnarchive: () async {
              final repo = await ref.read(
                expenseCategoryRepositoryProvider.future,
              );
              await repo.unarchive(cat.id);
            },
            onDelete: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除类目'),
                  content: Text('彻底删除「${cat.name}」？历史支出仍会保留，但不再标注此类目。'),
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
              final repo = await ref.read(
                expenseCategoryRepositoryProvider.future,
              );
              await repo.softDelete(cat.id);
            },
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.category,
    required this.index,
    required this.onEdit,
    required this.onArchive,
  });

  final ExpenseCategory category;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final accent =
        category.accentColor ?? Theme.of(context).colorScheme.primary;
    return AppDismissibleListTile(
      dismissibleKey: ValueKey('dis-${category.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onArchive();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 6),
            Text(
              '归档',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(category.iconData, color: accent),
        ),
        title: Text(category.name),
        subtitle: category.parentId == null ? null : const Text('子类目'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({
    super.key,
    required this.category,
    required this.onUnarchive,
    required this.onDelete,
  });

  final ExpenseCategory category;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(category.iconData, color: theme.colorScheme.outline),
      title: Text(
        category.name,
        style: TextStyle(color: theme.colorScheme.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onUnarchive, child: const Text('恢复')),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '彻底删除',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

void _showEditor(BuildContext context, WidgetRef ref, ExpenseCategory? cat) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CategoryEditor(initial: cat),
      );
    },
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.initial});

  final ExpenseCategory? initial;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  final _nameController = TextEditingController();
  String _icon = 'category';
  String? _color;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _nameController.text = c.name;
      _icon = c.icon ?? 'category';
      _color = c.color;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(expenseCategoryRepositoryProvider.future);
      if (widget.initial == null) {
        await repo.create(
          name: _nameController.text.trim(),
          icon: _icon,
          color: _color,
        );
      } else {
        await repo.update(
          widget.initial!.id,
          name: _nameController.text.trim(),
          icon: _icon,
          color: _color,
          clearColor: _color == null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initial == null ? '新建类目' : '编辑类目',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.s12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '类目名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.s12),
            Text('图标', style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.s8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kExpenseCategoryIcons.entries)
                  AppChoiceChip(
                    selected: entry.key == _icon,
                    label: Icon(entry.value, size: 20),
                    onSelected: (_) => setState(() => _icon = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: Spacing.s8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? '保存中…' : '保存'),
                ),
              ],
            ),
            const SizedBox(height: Spacing.s8),
          ],
        ),
      ),
    );
  }
}
