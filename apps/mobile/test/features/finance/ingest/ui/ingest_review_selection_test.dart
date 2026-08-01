import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_review_selection.dart';

void main() {
  test('selection preserves insertion order and prevents duplicates', () {
    final selection = IngestReviewSelection();

    selection.setSelected('a', selected: true);
    selection.setSelected('b', selected: true);
    selection.setSelected('a', selected: true);

    expect(selection.selectedIds, <String>['b', 'a']);
    expect(selection.isSelected('a'), isTrue);

    selection.setSelected('a', selected: false);
    expect(selection.selectedIds, <String>['b']);
  });

  test('focus offset starts at an edge and clamps within the list', () {
    final selection = IngestReviewSelection();
    const ids = <String>['a', 'b', 'c'];

    expect(selection.focusByOffset(ids, 1), 'a');
    expect(selection.focusByOffset(ids, -1), 'c');

    selection.focus('b');
    expect(selection.focusByOffset(ids, 1), 'c');
    selection.focus('c');
    expect(selection.focusByOffset(ids, 1), 'c');
  });

  test('reconcile prunes stale selection and repairs focus', () {
    final selection = IngestReviewSelection()
      ..setSelected('stale', selected: true)
      ..setSelected('kept', selected: true)
      ..focus('stale');

    expect(
      selection.needsReconcile(<String>{'kept'}, fallbackFocusId: 'kept'),
      isTrue,
    );
    selection.reconcile(<String>{'kept'}, fallbackFocusId: 'kept');

    expect(selection.selectedIds, <String>['kept']);
    expect(selection.focusedId, 'kept');
    expect(
      selection.needsReconcile(<String>{'kept'}, fallbackFocusId: 'kept'),
      isFalse,
    );
  });

  test('removeAll clears only completed ids', () {
    final selection = IngestReviewSelection()
      ..setSelected('a', selected: true)
      ..setSelected('b', selected: true)
      ..setSelected('c', selected: true);

    selection.removeAll(<String>{'a', 'c'});

    expect(selection.selectedIds, <String>['b']);
  });
}
