import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blueprint doc 15 §8.4 — "空态不许是死路": every `AppEmptyState` should
/// carry an `action` (or be the `.error` factory, which carries a retry).
///
/// A handful of states are legitimately quiet (a done-state rendered in
/// empty-state chrome, a picker whose exit affordance sits above the empty
/// body, a hint that points at an on-page section). Those are enumerated
/// here; anything new without an action fails the ratchet instead of
/// shipping a dead end.
void main() {
  test('AppEmptyState call sites carry an action (ratcheted)', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('design_system/widgets/app_empty_state'))
        .toList(growable: false);

    final offenders = <String>[];
    for (final file in files) {
      final text = file.readAsStringSync();
      var index = text.indexOf('AppEmptyState(');
      while (index != -1) {
        final end = _matchingParen(text, index + 'AppEmptyState'.length);
        final call = text.substring(index, end);
        if (!call.contains('action:')) {
          final line = '\n'.allMatches(text.substring(0, index)).length + 1;
          offenders.add('${file.path}:$line');
        }
        index = text.indexOf('AppEmptyState(', end);
      }
    }

    // Documented quiet states — shrink this list, never grow it.
    const allowlist = <String>{
      // Done-state rendered in empty-state chrome (success, not a dead end).
      'lib/features/finance/monthly_close/ui/monthly_close_page.dart',
      // Hint text points at the Sources section on the same page.
      'lib/features/health/ui/metric_grid.dart',
      // Picker sheets: the clear/none exit tile sits directly above.
      'lib/features/execution/ui/execution_relation_picker.dart',
      // Journal fills itself from recorded trades; true-empty explains it.
      'lib/features/finance/options_income/ui/income_planner/journal.dart',
    };

    final unexpected = offenders
        .where((o) => !allowlist.any(o.startsWith))
        .toList(growable: false);

    expect(
      unexpected,
      isEmpty,
      reason:
          'AppEmptyState without an action CTA (blueprint §8.4). Either give '
          'the state a way forward or add it to the documented allowlist:\n'
          '${unexpected.join('\n')}',
    );
  });
}

int _matchingParen(String text, int openIndex) {
  assert(text[openIndex] == '(');
  var depth = 0;
  for (var i = openIndex; i < text.length; i++) {
    final ch = text[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return text.length;
}
