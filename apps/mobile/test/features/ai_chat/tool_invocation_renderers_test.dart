import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/renderers/tool_invocation_renderers.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/tool_invocation_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

ToolInvocation _inv(String name, Object? output) => ToolInvocation(
  id: 't',
  name: name,
  input: const <String, Object?>{},
  output: output,
);

/// Wave 41 — Forui's `FTappable` decomposes at build time, so finder
/// by type doesn't resolve. The card now ships an explicit Key on the
/// header tap target; tests drive expansion via that key.
const _headerKey = Key('tool-invocation-card-header');

Future<void> _expandCard(WidgetTester tester) async {
  await tester.tap(find.byKey(_headerKey));
  await tester.pumpAndSettle();
}

Future<void> _expandCardAt(WidgetTester tester, int index) async {
  final target = find.byKey(_headerKey).at(index);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('renderToolOutput', () {
    testWidgets('get_holdings → mini holdings table', (tester) async {
      const output = <String, Object?>{
        'holdings': <String, Object?>{
          'a-1': <String, Object?>{
            'asset_id': 'a-1',
            'symbol': 'AAPL',
            'name': 'Apple Inc.',
            'net_quantity': 50,
            'avg_unit_cost': 150,
            'cost_basis': 7500,
            'currency': 'USD',
          },
          'a-2': <String, Object?>{
            'asset_id': 'a-2',
            'symbol': 'TSLA',
            'name': 'Tesla',
            'net_quantity': 10,
            'avg_unit_cost': 200,
            'cost_basis': 2000,
            'currency': 'USD',
          },
        },
      };

      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('get_holdings', output))),
      );
      await _expandCard(tester);

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('TSLA'), findsOneWidget);
      expect(find.text('资产'), findsOneWidget);
      expect(find.text('数量'), findsOneWidget);
      expect(find.text('成本'), findsOneWidget);
      expect(find.text('查看原始数据'), findsOneWidget);
    });

    testWidgets('compute_xirr → big rate + range label', (tester) async {
      const output = <String, Object?>{
        'scope': 'portfolio',
        'rate': 0.1234,
        'from': '2025-04-30T00:00:00Z',
        'to': '2026-04-30T00:00:00Z',
        'flows': <Object?>[
          <String, Object?>{'date': '2025-05-01T00:00:00Z', 'amount': -1000},
          <String, Object?>{'date': '2026-04-30T00:00:00Z', 'amount': 1200},
        ],
      };

      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('compute_xirr', output))),
      );
      await _expandCard(tester);

      expect(find.text('组合整体'), findsOneWidget);
      expect(find.textContaining('12.34%'), findsOneWidget);
      expect(find.textContaining('2 条现金流'), findsOneWidget);
    });

    testWidgets('compute_xirr → null rate falls through to a friendly note', (
      tester,
    ) async {
      const output = <String, Object?>{
        'scope': 'portfolio',
        'rate': null,
        'flows': <Object?>[],
      };

      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('compute_xirr', output))),
      );
      await _expandCard(tester);

      expect(find.textContaining('无法计算'), findsOneWidget);
    });

    testWidgets('compute_net_worth → end value + sparkline + range', (
      tester,
    ) async {
      const output = <String, Object?>{
        'from': '2026-01-01T00:00:00Z',
        'to': '2026-04-01T00:00:00Z',
        'granularity': 'month',
        'series': <Object?>[
          <String, Object?>{
            'date': '2026-01-01T00:00:00Z',
            'value': 100000,
            'currency': 'CNY',
          },
          <String, Object?>{
            'date': '2026-02-01T00:00:00Z',
            'value': 105000,
            'currency': 'CNY',
          },
          <String, Object?>{
            'date': '2026-03-01T00:00:00Z',
            'value': 108000,
            'currency': 'CNY',
          },
          <String, Object?>{
            'date': '2026-04-01T00:00:00Z',
            'value': 112000,
            'currency': 'CNY',
          },
        ],
      };

      await tester.pumpWidget(
        _wrap(
          ToolInvocationCard(invocation: _inv('compute_net_worth', output)),
        ),
      );
      await _expandCard(tester);

      expect(find.text('累计净现金流'), findsOneWidget);
      expect(find.textContaining('4 个采样点'), findsOneWidget);
    });

    testWidgets('get_net_worth_summary → monthly cumulative sparkline', (
      tester,
    ) async {
      const output = <String, Object?>{
        'from': '2026-01',
        'to': '2026-04',
        'series': <Object?>[
          <String, Object?>{
            'year_month': '2026-01',
            'cumulative_minor': '10000000',
            'net_flow_minor': '10000000',
            'currency': 'CNY',
          },
          <String, Object?>{
            'year_month': '2026-02',
            'cumulative_minor': '10500000',
            'net_flow_minor': '500000',
            'currency': 'CNY',
          },
          <String, Object?>{
            'year_month': '2026-03',
            'cumulative_minor': '10800000',
            'net_flow_minor': '300000',
            'currency': 'CNY',
          },
          <String, Object?>{
            'year_month': '2026-04',
            'cumulative_minor': '11200000',
            'net_flow_minor': '400000',
            'currency': 'CNY',
          },
        ],
      };

      await tester.pumpWidget(
        _wrap(
          ToolInvocationCard(invocation: _inv('get_net_worth_summary', output)),
        ),
      );
      await _expandCard(tester);

      expect(find.text('累计净现金流'), findsOneWidget);
      expect(find.textContaining('4 个采样点'), findsOneWidget);
      expect(find.text('计算净资产'), findsOneWidget);
    });

    testWidgets('list_payment_accounts → compact account list', (tester) async {
      const output = <String, Object?>{
        'status': 'ready',
        'purpose': 'record_expense',
        'total_count': 2,
        'truncated': false,
        'accounts': <Object?>[
          <String, Object?>{
            'id': 'acct-checking',
            'name': 'Flow Checking',
            'type': 'bank',
            'currency': 'USD',
          },
          <String, Object?>{
            'id': 'acct-cash',
            'name': 'Daily Cash',
            'type': 'cash',
            'currency': 'USD',
          },
        ],
      };

      await tester.pumpWidget(
        _wrap(
          ToolInvocationCard(invocation: _inv('list_payment_accounts', output)),
        ),
      );
      await _expandCard(tester);

      expect(find.text('可用支付账户'), findsOneWidget);
      expect(find.text('Flow Checking'), findsOneWidget);
      expect(find.text('Daily Cash'), findsOneWidget);
      expect(find.text('bank · USD'), findsOneWidget);
    });

    testWidgets('get_industry_breakdown → top 3 + others summary', (
      tester,
    ) async {
      const output = <String, Object?>{
        'total': 10000,
        'buckets': <Object?>[
          <String, Object?>{
            'label': 'Technology',
            'cost_basis': 5000,
            'share': 0.5,
            'currency': 'USD',
          },
          <String, Object?>{
            'label': 'Healthcare',
            'cost_basis': 2500,
            'share': 0.25,
            'currency': 'USD',
          },
          <String, Object?>{
            'label': 'Energy',
            'cost_basis': 1500,
            'share': 0.15,
            'currency': 'USD',
          },
          <String, Object?>{
            'label': 'Real Estate',
            'cost_basis': 1000,
            'share': 0.10,
            'currency': 'USD',
          },
        ],
      };

      await tester.pumpWidget(
        _wrap(
          ToolInvocationCard(
            invocation: _inv('get_industry_breakdown', output),
          ),
        ),
      );
      await _expandCard(tester);

      expect(find.text('Technology'), findsOneWidget);
      expect(find.text('Healthcare'), findsOneWidget);
      expect(find.text('Energy'), findsOneWidget);
      expect(find.text('Real Estate'), findsNothing);
      expect(find.textContaining('其他 1 类'), findsOneWidget);
    });

    testWidgets('get_risk_alerts → severity-tinted tile + share', (
      tester,
    ) async {
      const output = <String, Object?>{
        'alerts': <Object?>[
          <String, Object?>{
            'kind': 'asset_concentration',
            'asset_id': 'a-1',
            'symbol': 'AAPL',
            'share': 0.45,
            'threshold': 0.20,
            'severity': 'high',
            'message': '单一持仓占比 45.0% 超过 20% 警戒线',
          },
        ],
      };

      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('get_risk_alerts', output))),
      );
      await _expandCard(tester);

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.textContaining('单一持仓占比'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
    });

    testWidgets('get_risk_alerts empty list → positive empty state', (
      tester,
    ) async {
      const output = <String, Object?>{'alerts': <Object?>[]};
      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('get_risk_alerts', output))),
      );
      await _expandCard(tester);
      expect(find.text('没有触发的风险预警'), findsOneWidget);
    });

    testWidgets('unknown tool → falls back to raw JSON view', (tester) async {
      const output = <String, Object?>{'foo': 'bar'};
      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('mystery_tool', output))),
      );
      await _expandCard(tester);
      // No specialized renderer → no toggle, just JSON.
      expect(find.text('查看原始数据'), findsNothing);
      expect(find.textContaining('"foo"'), findsOneWidget);
    });

    testWidgets('"查看 raw JSON" toggle reveals the raw payload', (tester) async {
      const output = <String, Object?>{
        'holdings': <String, Object?>{
          'a-1': <String, Object?>{
            'asset_id': 'a-1',
            'symbol': 'AAPL',
            'net_quantity': 1,
            'avg_unit_cost': 1,
            'cost_basis': 1,
          },
        },
      };
      await tester.pumpWidget(
        _wrap(ToolInvocationCard(invocation: _inv('get_holdings', output))),
      );
      await _expandCard(tester);
      expect(find.textContaining('"asset_id"'), findsNothing);
      await tester.tap(find.text('查看原始数据'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"asset_id"'), findsOneWidget);
      expect(find.text('返回精简视图'), findsOneWidget);
    });

    testWidgets(
      'selected semantic/vision checklist surfaces stay readable at phone width',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(360, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        try {
          const netWorth = <String, Object?>{
            'from': '2026-01',
            'to': '2026-03',
            'series': <Object?>[
              <String, Object?>{
                'year_month': '2026-01',
                'cumulative_minor': '10000000',
                'currency': 'CNY',
              },
              <String, Object?>{
                'year_month': '2026-02',
                'cumulative_minor': '11600000',
                'currency': 'CNY',
              },
              <String, Object?>{
                'year_month': '2026-03',
                'cumulative_minor': '12800000',
                'currency': 'CNY',
              },
            ],
          };
          const allocation = <String, Object?>{
            'buckets': <Object?>[
              <String, Object?>{
                'bucket_key': 'stock',
                'currency': 'CNY',
                'total_cost_minor': '8000000',
                'position_count': 2,
                'weight': 0.625,
              },
              <String, Object?>{
                'bucket_key': 'cash',
                'currency': 'CNY',
                'total_cost_minor': '4800000',
                'position_count': 1,
                'weight': 0.375,
              },
            ],
          };
          const accounts = <String, Object?>{
            'status': 'ready',
            'purpose': 'record_expense',
            'total_count': 2,
            'accounts': <Object?>[
              <String, Object?>{
                'id': 'acct-pay',
                'name': 'Daily Checking',
                'type': 'bank',
                'currency': 'CNY',
              },
              <String, Object?>{
                'id': 'acct-cash',
                'name': 'Wallet Cash',
                'type': 'cash',
                'currency': 'CNY',
              },
            ],
          };

          await tester.pumpWidget(
            _wrap(
              Column(
                children: [
                  ToolInvocationCard(
                    invocation: _inv('get_net_worth_summary', netWorth),
                  ),
                  ToolInvocationCard(
                    invocation: _inv('get_asset_allocation', allocation),
                  ),
                  ToolInvocationCard(
                    invocation: _inv('list_payment_accounts', accounts),
                  ),
                ],
              ),
            ),
          );
          for (var i = 0; i < 3; i++) {
            await _expandCardAt(tester, i);
          }

          expect(tester.takeException(), isNull);
          expect(find.text('累计净现金流'), findsOneWidget);
          expect(find.text('stock'), findsOneWidget);
          expect(find.text('cash'), findsOneWidget);
          expect(find.text('可用支付账户'), findsOneWidget);
          expect(find.text('Daily Checking'), findsOneWidget);
          expect(find.text('Wallet Cash'), findsOneWidget);
          expect(tester.getSemantics(find.text('累计净现金流')).label, '累计净现金流');
          expect(
            tester.getSemantics(find.text('Daily Checking')).label,
            'Daily Checking',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  });

  group('isOversizedToolPayload', () {
    test('true when holdings map exceeds 50 entries', () {
      expect(
        isOversizedToolPayload('get_holdings', <String, Object?>{
          'holdings': <String, Object?>{
            for (var i = 0; i < 51; i++) 'a-$i': <String, Object?>{},
          },
        }),
        isTrue,
      );
    });

    test('false for unknown tool', () {
      expect(
        isOversizedToolPayload('mystery', <String, Object?>{
          'journal_entries': List.filled(100, <String, Object?>{}),
        }),
        isFalse,
      );
    });
  });
}
