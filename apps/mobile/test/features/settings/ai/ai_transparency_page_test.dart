import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/trace/trace.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_transparency_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/test_app_theme.dart';

void main() {
  group('summarizeContextBlockTraceWindow', () {
    test('aggregates only traces with ContextBlock sizing attributes', () {
      final summary = summarizeContextBlockTraceWindow([
        _trace('req-1', blockBytes: 1024),
        _trace('req-2'),
        _trace('req-3', blockBytes: 2048),
        _trace('req-4', blockBytes: 4096),
      ]);

      expect(summary.windowCount, 4);
      expect(summary.sampleCount, 3);
      expect(summary.sampleCoveragePercent, 75);
      expect(summary.avgBytes, 2389);
      expect(summary.p95Bytes, 4096);
    });

    test('returns an empty summary when no trace has sizing attributes', () {
      final summary = summarizeContextBlockTraceWindow([
        _trace('req-1'),
        _trace('req-2'),
      ]);

      expect(summary.windowCount, 2);
      expect(summary.hasSamples, isFalse);
      expect(summary.avgBytes, 0);
    });
  });

  group('AiTransparencyPage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows ContextBlock sample metrics in the aggregate header', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final store = InMemoryAiTraceStore();
      await store.append(_trace('req-1', blockBytes: 1024));
      await store.append(_trace('req-2', blockBytes: 4096));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            aiTraceStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            builder: buildTestAppTheme,
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
    });
  });
}

AiTrace _trace(String requestId, {int? blockBytes}) {
  final attrs = blockBytes == null
      ? null
      : <String, Object?>{'context_blocks_json_bytes': blockBytes};
  return AiTrace(
    requestId: requestId,
    startedAtIso: '2026-06-19T00:00:00.000Z',
    intent: const IntentHint(
      domain: AiDomain.shell(),
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
