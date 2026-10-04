part of '../ingest_review_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewGroups on _IngestReviewPageState {
  List<Object> _queueEntries(IngestReviewViewData data) => [
    for (final group in data.groups)
      if (group.items.length == 1)
        group.items.single
      else ...[
        group,
        if (_expandedGroups.contains(group.key)) ...group.items,
      ],
  ];

  Key _queueEntryKey(Object entry) => switch (entry) {
    IngestReviewGroup group => ValueKey(('ingest-group', group.key)),
    IngestReviewItem item => ValueKey('ingest-row-${item.draft.draftId}'),
    _ => throw StateError('Unknown review row'),
  };

  Widget _groupRow(IngestReviewGroup group) {
    final l10n = AppLocalizations.of(context);
    final first = group.items.first.draft;
    final expanded = _expandedGroups.contains(group.key);
    final selectable = group.items
        .where((item) => !item.recoveryUnreadable)
        .toList();
    final selectedCount = selectable
        .where((item) => _selection.isSelected(item.draft.draftId))
        .length;
    final categories = group.items
        .map(
          (item) =>
              _categoryLabel(l10n, ingestReviewCategory(item.draft.parsed)),
        )
        .toSet();
    final title = _grouping == IngestReviewGrouping.category
        ? _categoryLabel(l10n, ingestReviewCategory(first.parsed))
        : first.parsed.description;
    final editable = group.items.any(
      (item) =>
          item.isOrdinaryPending &&
          !_pendingFinalize.containsKey(item.draft.draftId) &&
          (item.draft.parsed.kind == IngestTransactionKind.expense ||
              item.draft.parsed.kind == IngestTransactionKind.income),
    );
    final attention = group.items
        .where(
          (item) =>
              item.blocksApply ||
              _pendingFinalize.containsKey(item.draft.draftId) ||
              item.draft.verdict != DedupVerdict.newTxn ||
              _attentionIds.contains(item.draft.draftId),
        )
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.theme.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ReviewCheckbox(
                key: ValueKey('ingest-group-select-${first.draftId}'),
                value: selectedCount == 0
                    ? false
                    : selectedCount == selectable.length
                    ? true
                    : null,
                semanticLabel: l10n.ingestSelectGroup(selectable.length, title),
                onChange: _isBusy || selectable.isEmpty
                    ? null
                    : (_) => setState(() {
                        final ids = selectable.map(
                          (item) => item.draft.draftId,
                        );
                        if (selectedCount == selectable.length) {
                          _selection.removeAll(ids.toSet());
                        } else {
                          _selection.selectAll(ids);
                        }
                      }),
              ),
              Expanded(
                child: Text(
                  title,
                  style: context.strongLabelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppIconButton(
                key: ValueKey('ingest-group-expand-${first.draftId}'),
                tooltip: expanded
                    ? l10n.ingestCollapseGroup
                    : l10n.ingestExpandGroup,
                icon: expanded
                    ? FLucideIcons.chevronUp
                    : FLucideIcons.chevronDown,
                onPress: _isBusy
                    ? null
                    : () => setState(() {
                        if (expanded) {
                          _expandedGroups.remove(group.key);
                        } else {
                          _expandedGroups.add(group.key);
                        }
                      }),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.s12),
            child: Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.ingestGroupCount(group.items.length),
                  style: context.bodyCaptionStyle,
                ),
                Text(group.key.currency, style: context.bodyCaptionStyle),
                if (_grouping == IngestReviewGrouping.description)
                  Text(
                    categories.length == 1
                        ? categories.single
                        : l10n.ingestMixedCategories,
                    style: context.bodyCaptionStyle,
                  ),
                if (attention > 0)
                  Text(
                    l10n.ingestGroupAttention(attention),
                    style: context.bodyCaptionStyle,
                  ),
                if (editable)
                  AppQuietButton(
                    key: ValueKey('ingest-group-category-${first.draftId}'),
                    label: l10n.ingestBatchCategory,
                    onPress: _isBusy
                        ? null
                        : () => _editSelectedCategory(group.items),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDraftDetails(IngestReviewItem item) async {
    if (_isBusy) return;
    final id = item.draft.draftId;
    if (_selection.selectedIds.isNotEmpty) {
      if (!item.recoveryUnreadable) {
        _toggleSelection(id, !_selection.isSelected(id));
      }
      return;
    }
    _focusItem(id);
    await showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context).ingestReviewTitle,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref
              .watch(pendingIngestReviewItemsProvider)
              .value
              ?.where((item) => item.draft.draftId == id)
              .firstOrNull;
          if (current == null) {
            return Text(AppLocalizations.of(context).ingestNoMatchingDrafts);
          }
          void act(Future<void> Function() action) {
            unawaited(
              closeSheetThen(sheetContext, () async {
                if (mounted) await action();
              }),
            );
          }

          final draft = current.draft;
          final pending = current.pendingFinalize ?? _pendingFinalize[id];
          return _DraftCard(
            draft: draft,
            selected: false,
            selectable: false,
            focused: true,
            busy: _isBusy,
            pendingFinalize: pending != null,
            recoveryUnavailable: current.recoveryUnreadable,
            showSelection: false,
            onConfirm: () =>
                act(() => _confirm(draft, _currentData?.selectedAccountId)),
            onSkip: () => act(() => _skip(draft)),
            onEdit: () => act(() => _editDraft(draft)),
            onTransfer: () => act(() => _recordTransfer(draft)),
            onTrade: () => act(() => _recordTrade(draft)),
            onFinalize: pending == null
                ? null
                : () => act(() => _finalizeApplied(pending)),
            onSelectionChanged: (_) {},
            onFocus: () {},
          );
        },
      ),
    );
  }
}
