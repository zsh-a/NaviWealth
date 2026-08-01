/// Pure selection and keyboard-focus state for the Ingest review workspace.
///
/// Keeping this independent from Flutter lets the page delegate ordered
/// selection/focus mutations without coupling them to widget lifecycle code.
class IngestReviewSelection {
  final List<String> _selectedIds = <String>[];
  String? _focusedId;

  List<String> get selectedIds => List<String>.unmodifiable(_selectedIds);
  String? get focusedId => _focusedId;

  bool isSelected(String draftId) => _selectedIds.contains(draftId);
  bool isFocused(String draftId) => _focusedId == draftId;

  void setSelected(String draftId, {required bool selected}) {
    _selectedIds.remove(draftId);
    if (selected) _selectedIds.add(draftId);
  }

  void focus(String draftId) {
    _focusedId = draftId;
  }

  String? focusByOffset(List<String> orderedIds, int delta) {
    if (orderedIds.isEmpty) return null;
    final current = orderedIds.indexOf(_focusedId ?? '');
    final next = current < 0
        ? (delta > 0 ? 0 : orderedIds.length - 1)
        : (current + delta).clamp(0, orderedIds.length - 1);
    return orderedIds[next];
  }

  bool needsReconcile(Set<String> validIds, {String? fallbackFocusId}) {
    return !_selectedIds.every(validIds.contains) ||
        (!validIds.contains(_focusedId) && _focusedId != fallbackFocusId);
  }

  void reconcile(Set<String> validIds, {String? fallbackFocusId}) {
    _selectedIds.retainWhere(validIds.contains);
    if (!validIds.contains(_focusedId)) {
      _focusedId = fallbackFocusId;
    }
  }

  void removeAll(Set<String> draftIds) {
    _selectedIds.removeWhere(draftIds.contains);
  }
}
