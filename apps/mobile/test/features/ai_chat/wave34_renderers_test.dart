// Wave 34 — Domain renderer dispatch + empty-state contract.
//
// We don't pump the rendered widgets all the way to a finder graph (the
// pre-existing tool_invocation_renderers_test has _expandCard failures
// unrelated to this wave and we don't want to inherit the same fragile
// finder pattern). Instead we capture a BuildContext via a Builder,
// invoke `renderToolOutput` directly, and assert the returned widget
// type is correct + the dispatcher doesn't throw on malformed input.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/ui/tool_invocation_renderers.dart';

Future<Widget?> renderVia(
  WidgetTester tester,
  String tool,
  Object output,
) async {
  Widget? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) {
          captured = renderToolOutput(ctx, tool, output);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('Wave 34 dispatch returns a widget for each new tool', (
    tester,
  ) async {
    expect(
      await renderVia(tester, 'get_asset_allocation', <String, Object?>{
        'buckets': [
          {
            'bucket_dim': 'asset_type',
            'bucket_key': 'stock',
            'currency': 'USD',
            'total_cost_minor': '150000',
            'position_count': 2,
            'weight': 0.6,
          },
          {
            'bucket_dim': 'asset_type',
            'bucket_key': 'crypto',
            'currency': 'USD',
            'total_cost_minor': '100000',
            'position_count': 1,
            'weight': 0.4,
          },
        ],
      }),
      isA<AssetAllocationView>(),
    );
    expect(
      await renderVia(tester, 'get_recurring_patterns', <String, Object?>{
        'patterns': [
          {
            'id': 'netflix|USD',
            'merchant_key': 'netflix',
            'cadence': 'monthly',
            'currency': 'USD',
            'median_amount_minor': '999',
            'occurrences': 3,
            'last_seen_at': '2026-05-12T00:00:00Z',
          },
        ],
      }),
      isA<RecurringPatternsView>(),
    );
    expect(
      await renderVia(tester, 'get_subscription_changes', <String, Object?>{
        'changes': [
          {
            'id': 'netflix|USD',
            'merchant_key': 'netflix',
            'cadence': 'monthly',
            'currency': 'USD',
            'prev_amount_minor': '999',
            'new_amount_minor': '1299',
            'delta_ratio': 0.3,
            'since': '2026-04-01T00:00:00Z',
          },
        ],
      }),
      isA<SubscriptionChangesView>(),
    );
    expect(
      await renderVia(tester, 'get_refund_links', <String, Object?>{
        'links': [
          {
            'id': 'orig_1|ref_1',
            'original_txn_id': 'orig_1',
            'refund_txn_id': 'ref_1',
            'amount_minor': '4500',
            'currency': 'USD',
          },
        ],
      }),
      isA<RefundLinksView>(),
    );
  });

  testWidgets('empty payloads still return the typed widget', (tester) async {
    expect(
      await renderVia(tester, 'get_asset_allocation', <String, Object?>{
        'buckets': [],
      }),
      isA<AssetAllocationView>(),
    );
    expect(
      await renderVia(tester, 'get_recurring_patterns', <String, Object?>{
        'patterns': [],
      }),
      isA<RecurringPatternsView>(),
    );
    expect(
      await renderVia(tester, 'get_subscription_changes', <String, Object?>{
        'changes': [],
      }),
      isA<SubscriptionChangesView>(),
    );
    expect(
      await renderVia(tester, 'get_refund_links', <String, Object?>{
        'links': [],
      }),
      isA<RefundLinksView>(),
    );
  });

  testWidgets('malformed payload still resolves to a widget (no throw)', (
    tester,
  ) async {
    expect(
      await renderVia(tester, 'get_asset_allocation', <String, Object?>{}),
      isA<AssetAllocationView>(),
    );
    expect(
      await renderVia(tester, 'get_recurring_patterns', 'not-a-map'),
      isA<RecurringPatternsView>(),
    );
  });

  testWidgets('unrelated tool names return null', (tester) async {
    expect(
      await renderVia(tester, 'get_unknown_tool', <String, Object?>{}),
      isNull,
    );
  });

  testWidgets('new tools do not force raw-JSON fallback via oversize check', (
    tester,
  ) async {
    expect(
      isOversizedToolPayload('get_recurring_patterns', <String, Object?>{
        'patterns': <Object?>[],
      }),
      isFalse,
    );
    expect(
      isOversizedToolPayload('get_asset_allocation', <String, Object?>{
        'buckets': <Object?>[],
      }),
      isFalse,
    );
    expect(
      isOversizedToolPayload('get_subscription_changes', <String, Object?>{
        'changes': List<Map<String, Object?>>.generate(
          100,
          (i) => <String, Object?>{'merchant_key': 'm$i'},
        ),
      }),
      isFalse,
    );
  });
}
