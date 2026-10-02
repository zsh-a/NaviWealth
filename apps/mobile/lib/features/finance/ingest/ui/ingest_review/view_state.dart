part of '../ingest_review_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewViewState on _IngestReviewPageState {
  void _restoreReviewView(LocalFormDraftStore? store) {
    _viewSession?.dispose();
    _viewSession = store == null
        ? null
        : LocalFormDraftSession(store, 'finance.ingest.review-view');
    final saved = _viewSession?.pending;
    _viewSession?.accept();
    _query = saved?['query'] is String ? saved!['query']! as String : '';
    _search.text = _query;
    _filter =
        IngestReviewFilter.values
            .where((value) => value.name == saved?['filter'])
            .firstOrNull ??
        IngestReviewFilter.all;
    _sort =
        IngestReviewSort.values
            .where((value) => value.name == saved?['sort'])
            .firstOrNull ??
        IngestReviewSort.importOrder;
    _accountId = saved?['account'] is String
        ? saved!['account']! as String
        : null;
    _visibleLimit = saved?['limit'] is int
        ? (saved!['limit']! as int).clamp(100, 10000)
        : 100;
    _selection.clear();
    _selection.reconcile(const {});
    if (saved?['focus'] case final String id) _selection.focus(id);
    final offset = saved?['offset'];
    _restoreOffset = offset is num && offset.isFinite
        ? offset.toDouble().clamp(0.0, double.maxFinite)
        : 0;
    _projectionKey = null;
    _currentData = null;
    _previousReviewOrder = const [];
    _lastBatchOutcome = null;
    _lastUndoOffer = null;
    _attentionIds = {};
    _pendingFinalize.clear();
  }

  void _captureReviewView() {
    final session = _viewSession;
    if (session == null) {
      return;
    }
    session.capture({
      'query': _query,
      'filter': _filter.name,
      'sort': _sort.name,
      'account': _accountId,
      'limit': _visibleLimit,
      'focus': _selection.focusedId,
      'offset':
          _restoreOffset ??
          (_reviewScroll.hasClients ? _reviewScroll.offset : 0),
    });
  }

  void _restoreReviewScroll() {
    if (_restoreOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_reviewScroll.hasClients || _restoreOffset == null) {
        return;
      }
      final offset = _restoreOffset!;
      _restoreOffset = null;
      _reviewScroll.jumpTo(
        offset.clamp(0.0, _reviewScroll.position.maxScrollExtent),
      );
      _captureReviewView();
    });
  }
}
