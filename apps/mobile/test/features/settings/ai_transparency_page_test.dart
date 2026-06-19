import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/trace.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai_transparency_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('summarizeContextPackTraceWindow', () {
    test('aggregates only traces with ContextPack sizing attributes', () {
      final summary = summarizeContextPackTraceWindow([
        _trace('req-1', packBytes: 1024, appendixBytes: 256),
        _trace('req-2'),
        _trace('req-3', packBytes: 2048, appendixBytes: 512),
        _trace(
          'req-4',
          packBytes: 4096,
          appendixBytes: 900,
          appendixCapBytes: 1000,
        ),
      ]);

      expect(summary.windowCount, 4);
      expect(summary.sampleCount, 3);
      expect(summary.sampleCoveragePercent, 75);
      expect(summary.avgPackBytes, 2389);
      expect(summary.p95PackBytes, 4096);
      expect(summary.packBudgetBytes, 10000);
      expect(summary.p95PackBudgetPercent, 41);
      expect(summary.avgAppendixBytes, 556);
      expect(summary.p95AppendixBytes, 900);
      expect(summary.appendixCapBytes, 1000);
      expect(summary.p95AppendixCapPercent, 90);
    });

    test('returns an empty summary when no trace has sizing attributes', () {
      final summary = summarizeContextPackTraceWindow([
        _trace('req-1'),
        _trace('req-2'),
      ]);

      expect(summary.windowCount, 2);
      expect(summary.hasSamples, isFalse);
      expect(summary.avgPackBytes, 0);
      expect(summary.p95PackBudgetPercent, 0);
      expect(summary.p95AppendixCapPercent, 0);
    });
  });

  group('AiTransparencyPage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows ContextPack sample metrics in the aggregate header', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final store = InMemoryAiTraceStore();
      await store.append(
        _trace(
          'req-1',
          packBytes: 1024,
          appendixBytes: 256,
          appendixCapBytes: 1000,
        ),
      );
      await store.append(
        _trace(
          'req-2',
          packBytes: 4096,
          appendixBytes: 900,
          appendixCapBytes: 1000,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            aiTraceStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AiTransparencyPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ctx samples 2/2'), findsOneWidget);
      expect(find.text('ctx avg 2.5KB'), findsOneWidget);
      expect(find.text('ctx p95 4.0KB'), findsOneWidget);
      expect(find.text('ctx p95 41% budget'), findsOneWidget);
      expect(find.text('appendix avg 578B'), findsOneWidget);
      expect(find.text('appendix p95 90% cap'), findsOneWidget);
    });
  });
}

AiTrace _trace(
  String requestId, {
  int? packBytes,
  int? packBudgetBytes = 10000,
  int? appendixBytes,
  int? appendixCapBytes,
}) {
  final attrs = packBytes == null || appendixBytes == null
      ? null
      : <String, Object?>{
          'context_pack_json_bytes': packBytes,
          'context_pack_budget_bytes': ?packBudgetBytes,
          'context_appendix_bytes': appendixBytes,
          'context_appendix_cap_bytes': ?appendixCapBytes,
        };
  return AiTrace(
    requestId: requestId,
    startedAtIso: '2026-06-19T00:00:00.000Z',
    intent: const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.info,
    ),
    backend: Backend.device,
    budgetTier: BudgetTier.standard,
    routingReason: 'device_llm_direct',
    totalDurationMs: 100,
    spans: [
      AiSpan(
        id: 'turn',
        kind: AiSpanKind.turn,
        name: 'turn',
        startOffsetMs: 0,
        durationMs: 100,
        attributes: attrs,
      ),
    ],
  );
}
