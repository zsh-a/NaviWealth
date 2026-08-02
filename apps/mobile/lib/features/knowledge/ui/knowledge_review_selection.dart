part of 'knowledge_review_page.dart';

/// Shared selection toolbar + reorderable list for Review cards.
/// Encapsulates the `_selectedIds` set, `_ReviewSelectionToolbar`,
/// and `_ReviewReorderableList` pattern that all three cards repeat.
class _ReviewSelectableList<T> extends StatefulWidget {
  const _ReviewSelectableList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.actionLabel,
    required this.icon,
    required this.onBulkAction,
    required this.orderPrefsKey,
    required this.onOrderChanged,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(T item) itemBuilder;
  final String actionLabel;
  final IconData icon;
  final Future<void> Function(List<T> selected) onBulkAction;
  final String orderPrefsKey;
  final ValueChanged<List<String>> onOrderChanged;

  @override
  State<_ReviewSelectableList<T>> createState() =>
      _ReviewSelectableListState<T>();
}

class _ReviewSelectableListState<T> extends State<_ReviewSelectableList<T>> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final visibleIds = {for (final item in widget.items) widget.idOf(item)};
    _selectedIds.removeWhere((id) => !visibleIds.contains(id));
    final selected = widget.items
        .where((item) => _selectedIds.contains(widget.idOf(item)))
        .toList(growable: false);
    return Column(
      children: [
        _ReviewSelectionToolbar(
          selectedCount: selected.length,
          totalCount: widget.items.length,
          actionLabel: widget.actionLabel,
          icon: widget.icon,
          onSelectAll: () => setState(() {
            _selectedIds
              ..clear()
              ..addAll(visibleIds);
          }),
          onClear: () => setState(_selectedIds.clear),
          onRun: selected.isEmpty
              ? null
              : () async {
                  await widget.onBulkAction(selected);
                  if (mounted) setState(_selectedIds.clear);
                },
        ),
        const SizedBox(height: AppSpacing.s8),
        _ReviewReorderableList<T>(
          items: widget.items,
          idOf: widget.idOf,
          itemBuilder: (item) => _SelectableReviewRow(
            selected: _selectedIds.contains(widget.idOf(item)),
            onChanged: () => setState(
              () => _toggleReviewSelection(_selectedIds, widget.idOf(item)),
            ),
            child: widget.itemBuilder(item),
          ),
          onOrderChanged: widget.onOrderChanged,
        ),
      ],
    );
  }
}

class _ReviewCountHint extends StatelessWidget {
  const _ReviewCountHint({
    required this.visibleCount,
    required this.totalCount,
  });

  final int visibleCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = visibleCount >= totalCount
        ? l10n.knowledgeReviewTotalCount(totalCount)
        : l10n.knowledgeReviewVisibleCount(visibleCount, totalCount);
    return Row(
      children: [
        AppBadge(
          label: '$totalCount',
          icon: FLucideIcons.listChecks,
          size: AppBadgeSize.compact,
          tone: AppBadgeTone.info,
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(child: Text(label, style: context.captionStyle)),
      ],
    );
  }
}

class _ReviewBulkActionButton extends StatefulWidget {
  const _ReviewBulkActionButton({
    required this.label,
    required this.icon,
    required this.onPress,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPress;

  @override
  State<_ReviewBulkActionButton> createState() =>
      _ReviewBulkActionButtonState();
}

class _ReviewBulkActionButtonState extends State<_ReviewBulkActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPress();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBusyButton(
      label: widget.label,
      onPress: _run,
      busy: _busy,
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: Icon(widget.icon, size: AppIconSizes.xs),
      busyPrefix: const FCircularProgress(
        size: FCircularProgressSizeVariant.xs,
      ),
      busyLabel: AppLocalizations.of(context).commonSaving,
    );
  }
}

class _ReviewSelectionToolbar extends StatefulWidget {
  const _ReviewSelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.actionLabel,
    required this.icon,
    required this.onSelectAll,
    required this.onClear,
    required this.onRun,
  });

  final int selectedCount;
  final int totalCount;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final Future<void> Function()? onRun;

  @override
  State<_ReviewSelectionToolbar> createState() =>
      _ReviewSelectionToolbarState();
}

class _ReviewSelectionToolbarState extends State<_ReviewSelectionToolbar> {
  bool _busy = false;

  Future<void> _run() async {
    final run = widget.onRun;
    if (_busy || run == null) return;
    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasSelection = widget.selectedCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        children: [
          Text(
            l10n.knowledgeReviewSelectedCount(widget.selectedCount),
            style: context.captionStyle,
          ),
          const Spacer(),
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            onPress: widget.totalCount == 0 ? null : widget.onSelectAll,
            child: Text(l10n.knowledgeReviewSelectAll),
          ),
          const SizedBox(width: AppSpacing.s4),
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            onPress: hasSelection ? widget.onClear : null,
            child: Text(l10n.knowledgeReviewClearSelection),
          ),
          if (hasSelection) ...[
            const SizedBox(width: AppSpacing.s4),
            AppBusyButton(
              label: widget.actionLabel,
              onPress: _run,
              busy: _busy,
              variant: FButtonVariant.primary,
              size: FButtonSizeVariant.sm,
              prefix: Icon(widget.icon, size: AppIconSizes.xs),
              busyPrefix: const FCircularProgress(
                size: FCircularProgressSizeVariant.xs,
              ),
              busyLabel: AppLocalizations.of(context).commonSaving,
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectableReviewRow extends StatelessWidget {
  const _SelectableReviewRow({
    required this.selected,
    required this.onChanged,
    required this.child,
  });

  final bool selected;
  final VoidCallback onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s8),
          child: FCheckbox(value: selected, onChange: (_) => onChanged()),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Compact icon-only action button for review rows. Shows a spinner
/// while busy, the action icon otherwise. Much smaller footprint than
/// the full text button it replaces.
class _ReviewIconButton extends StatelessWidget {
  const _ReviewIconButton({
    required this.icon,
    required this.busy,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final bool busy;
  final String tooltip;
  final Future<bool> Function() onPress;

  @override
  Widget build(BuildContext context) {
    return AppIconButton.softPrimaryTile(
      icon: icon,
      tooltip: tooltip,
      onPress: () => onPress(),
      busy: busy,
    );
  }
}

class _SwipeReviewAction extends StatelessWidget {
  const _SwipeReviewAction({
    required this.dismissKey,
    required this.label,
    required this.icon,
    required this.onComplete,
    required this.child,
  });

  final Key dismissKey;
  final String label;
  final IconData icon;
  final Future<bool> Function() onComplete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppDismissible(
      itemKey: dismissKey,
      tone: AppDismissibleTone.primary,
      icon: icon,
      label: label,
      borderRadius: AppRadius.sm,
      confirm: onComplete,
      // The review flow re-flows its own list after completion.
      removeRow: false,
      child: child,
    );
  }
}

class _ReviewReorderableList<T> extends StatefulWidget {
  const _ReviewReorderableList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onOrderChanged,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(T item) itemBuilder;
  final ValueChanged<List<String>> onOrderChanged;

  @override
  State<_ReviewReorderableList<T>> createState() =>
      _ReviewReorderableListState<T>();
}

class _ReviewReorderableListState<T> extends State<_ReviewReorderableList<T>> {
  late List<T> _items = List<T>.of(widget.items);

  @override
  void didUpdateWidget(covariant _ReviewReorderableList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = _items.map(widget.idOf).join('\u0001');
    final nextIds = widget.items.map(widget.idOf).join('\u0001');
    if (oldIds != nextIds) {
      _items = List<T>.of(widget.items);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ReorderableList(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final moved = _items.removeAt(oldIndex);
          _items.insert(newIndex, moved);
        });
        widget.onOrderChanged(_items.map(widget.idOf).toList(growable: false));
      },
      itemBuilder: (context, index) {
        final item = _items[index];
        return Row(
          key: ValueKey<String>('review-order-${widget.idOf(item)}'),
          children: [
            Expanded(child: widget.itemBuilder(item)),
            const SizedBox(width: AppSpacing.s4),
            Semantics(
              button: true,
              label: AppLocalizations.of(context).knowledgeReviewReorder,
              child: ReorderableDragStartListener(
                index: index,
                child: SizedBox.square(
                  dimension: AppControlHeights.touchTarget,
                  child: Center(
                    child: Icon(
                      FLucideIcons.gripVertical,
                      size: AppIconSizes.xs,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
