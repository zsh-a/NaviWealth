part of '../ingest_review_page.dart';

// Extension methods on a State subclass legitimately call setState, which
// the analyzer flags as protected outside the class body.
// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewFocusKeys on _IngestReviewPageState {
  void _focusItem(String draftId, {bool requestFocus = true}) {
    if (_isBusy) return;
    setState(() {
      _selection.focus(draftId);
      final data = _currentData;
      if (data != null) {
        for (final group in data.groups) {
          if (group.items.any((item) => item.draft.draftId == draftId)) {
            _expandedGroups.add(group.key);
            break;
          }
        }
        final index = _queueEntries(data).indexWhere(
          (entry) =>
              entry is IngestReviewItem && entry.draft.draftId == draftId,
        );
        if (index >= _visibleLimit) _visibleLimit = ((index ~/ 100) + 1) * 100;
      }
    });
    if (requestFocus) _masterFocus.requestFocus();
  }

  void _moveFocus(IngestReviewViewData data, int delta) {
    if (_isBusy || isTextInputFocused() || data.items.isEmpty) return;
    final next = _selection.focusByOffset(
      data.reviewOrder
          .map((item) => item.draft.draftId)
          .toList(growable: false),
      delta,
    );
    if (next != null) _focusItem(next);
  }

  KeyEventResult _onMasterKey(
    IngestReviewViewData data,
    KeyEvent event, {
    required bool wide,
  }) {
    if (!_masterFocus.hasPrimaryFocus || _isBusy || isTextInputFocused()) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveFocus(data, 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(data, -1);
      return KeyEventResult.handled;
    }
    final focused = data.items
        .where((item) => _selection.isFocused(item.draft.draftId))
        .firstOrNull;
    if (focused == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!focused.recoveryUnreadable) {
        _toggleSelection(
          focused.draft.draftId,
          !_selection.isSelected(focused.draft.draftId),
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (wide) {
        _focusItem(focused.draft.draftId);
      } else {
        unawaited(_openDraftDetails(focused));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scheduleSelectionPrune(
    List<IngestReviewItem> items, {
    required bool ensureFocus,
  }) {
    final ids = items.map((item) => item.draft.draftId).toSet();
    final fallbackFocusId = ensureFocus ? _preferredFocusId(items) : null;
    _previousReviewOrder = items
        .map((item) => item.draft.draftId)
        .toList(growable: false);
    if (!_selection.needsReconcile(ids, fallbackFocusId: fallbackFocusId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(
        () => _selection.reconcile(ids, fallbackFocusId: fallbackFocusId),
      );
    });
  }

  String? _preferredFocusId(List<IngestReviewItem> items) {
    if (items.isEmpty) return null;
    final focusedId = _selection.focusedId;
    final oldIndex = _previousReviewOrder.indexOf(focusedId ?? '');
    final available = items.map((item) => item.draft.draftId).toSet();
    if (oldIndex >= 0 && !available.contains(focusedId)) {
      for (
        var index = oldIndex + 1;
        index < _previousReviewOrder.length;
        index++
      ) {
        if (available.contains(_previousReviewOrder[index])) {
          return _previousReviewOrder[index];
        }
      }
      for (var index = oldIndex - 1; index >= 0; index--) {
        if (available.contains(_previousReviewOrder[index])) {
          return _previousReviewOrder[index];
        }
      }
    }
    for (final item in items) {
      final draftId = item.draft.draftId;
      final pending = item.pendingFinalize ?? _pendingFinalize[draftId];
      if (!item.recoveryUnreadable &&
          (item.isOrdinaryPending || pending != null)) {
        return draftId;
      }
    }
    return items.first.draft.draftId;
  }
}
