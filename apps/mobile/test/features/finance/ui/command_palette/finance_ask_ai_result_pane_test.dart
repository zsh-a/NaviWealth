import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/transaction_input.dart';
import 'package:naviwealth/features/finance/ai_tools/query_plan/query_plan.dart';
import 'package:naviwealth/features/finance/ui/command_palette/finance_ask_ai_result_pane.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DateTime _frozenNow = DateTime.utc(2026, 5, 15);

TransactionInput _coffee(String id, DateTime when, int minorAbs) =>
    TransactionInput(
      id: id,
      description: 'Starbucks coffee',
      amountMinor: '-$minorAbs',
      currency: 'CNY',
      occurredAt: when,
    );

Widget _wrap(Widget child) {
  // Force zh so the assertions can match the Chinese surface text.
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('FinanceAskAiResultPane', () {
    testWidgets('renders structured result for a parseable NL query', (
      tester,
    ) async {
      final executor = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _coffee('c1', DateTime.utc(2026, 4, 3), 4500),
          _coffee('c2', DateTime.utc(2026, 4, 10), 5500),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          FinanceAskAiResultPane(
            query: '上月咖啡花了多少',
            executor: executor,
            now: _frozenNow,
          ),
        ),
      );
      await _settle(tester);

      // Title for the spending-by-category result lands.
      expect(find.text('支出分类'), findsOneWidget);
      // Local-processing badge is always visible while the pane is mounted.
      expect(find.text('本地处理'), findsOneWidget);
      // Summary line is "1 条" because both rows share the same hint key.
      expect(find.textContaining('条'), findsWidgets);
    });

    testWidgets('shows the irreversible guardrail message for write queries', (
      tester,
    ) async {
      final executor = InMemoryQueryPlanExecutor(transactions: const []);
      await tester.pumpWidget(
        _wrap(
          FinanceAskAiResultPane(
            query: '转账 ¥5000 给招行',
            executor: executor,
            now: _frozenNow,
          ),
        ),
      );
      await _settle(tester);

      expect(
        find.textContaining('不执行转账'),
        findsOneWidget,
        reason: '§5.10.6 — command palette must refuse NL-driven transfers',
      );
    });

    testWidgets('shows the no-local-match notice when nothing parses', (
      tester,
    ) async {
      final executor = InMemoryQueryPlanExecutor(transactions: const []);
      await tester.pumpWidget(
        _wrap(
          FinanceAskAiResultPane(
            query: 'tell me a joke about the federal reserve',
            executor: executor,
            now: _frozenNow,
          ),
        ),
      );
      await _settle(tester);

      expect(find.textContaining('暂无法本地解析'), findsOneWidget);
    });

    testWidgets('continue-in-chat link calls back with the trimmed query', (
      tester,
    ) async {
      final executor = InMemoryQueryPlanExecutor(transactions: const []);
      String? captured;
      await tester.pumpWidget(
        _wrap(
          FinanceAskAiResultPane(
            query: '  unrelated mystery  ',
            executor: executor,
            now: _frozenNow,
            onContinueInChat: (q) => captured = q,
          ),
        ),
      );
      await _settle(tester);

      // The pane renders both the no-match notice ("…可去 AI 历史里继续追问。")
      // and the link below it ("去 AI 历史继续追问 →"). The link is the
      // one that ends with the arrow glyph.
      final link = find.textContaining('继续追问 →');
      expect(link, findsOneWidget);
      await tester.tap(link);
      // FTappable schedules a 100ms press-feedback timer; drain it so
      // the test binding doesn't fail on leftover timers.
      await tester.pump(const Duration(milliseconds: 200));
      expect(captured, 'unrelated mystery');
    });

    testWidgets('rerunning with a new query refreshes the result', (
      tester,
    ) async {
      final executor = InMemoryQueryPlanExecutor(
        transactions: <TransactionInput>[
          _coffee('c1', DateTime.utc(2026, 4, 3), 4500),
        ],
      );

      Widget build(String q) => _wrap(
        FinanceAskAiResultPane(query: q, executor: executor, now: _frozenNow),
      );

      // Use a query with an explicit spending verb — `parseNlQuery`
      // requires both a spending intent and a category/range hint
      // before it'll return a SpendingByCategoryPlan.
      await tester.pumpWidget(build('上月咖啡花了多少'));
      await _settle(tester);
      expect(find.text('支出分类'), findsOneWidget);

      await tester.pumpWidget(build('转账 1000'));
      await _settle(tester);
      expect(find.textContaining('不执行转账'), findsOneWidget);
      expect(find.text('支出分类'), findsNothing);
    });
  });
}
