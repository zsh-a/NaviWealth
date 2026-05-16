// Wave 34 — reply_chips rule generator.
//
// suggestReplyChips now returns stable, locale-independent chip *ids*
// (localized to display text by `localizedReplyChip` at the UI layer),
// so these assertions are on ids rather than zh display strings.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/ui/reply_chips.dart';

void main() {
  test('returns 3 chips for explain_change intent', () {
    final chips = suggestReplyChips(invocationIntent: 'explain_change');
    expect(chips, hasLength(3));
    expect(chips, contains('compareLastPeriod'));
  });

  test('returns 3 chips for stress_test_plan intent', () {
    final chips = suggestReplyChips(invocationIntent: 'stress_test_plan');
    expect(chips, hasLength(3));
    expect(chips.first, 'marketDrop20');
  });

  test('tool-driven chip surfaces when matching tool was used', () {
    final chips = suggestReplyChips(
      invocationIntent: 'summarize_account',
      turnTools: {'get_recurring_patterns'},
    );
    expect(chips, contains('unusedSubscriptions'));
  });

  test('falls back to generic chips when no intent / no tools', () {
    final chips = suggestReplyChips();
    expect(chips, hasLength(3));
    expect(chips, contains('expandDetails'));
  });

  test('caps at 3 even when many tools + intent could contribute', () {
    final chips = suggestReplyChips(
      invocationIntent: 'compare_period',
      turnTools: {
        'get_asset_allocation',
        'get_recurring_patterns',
        'get_subscription_changes',
        'get_refund_links',
        'compute_xirr',
        'compute_net_worth',
      },
    );
    expect(chips, hasLength(3));
    // All 3 should be intent-specific (compare_period) — they take priority.
    expect(chips, containsAll(<String>['compareAnotherPeriod']));
  });

  test('no duplicates across rule passes', () {
    // Intent + a tool that maps to the same generic chip should not
    // double up.
    final chips = suggestReplyChips(
      invocationIntent: 'compare_period',
      turnTools: {'get_recurring_patterns'},
    );
    expect(chips.toSet().length, chips.length);
  });
}
