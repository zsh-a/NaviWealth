import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/perf/frame_timing_collector.dart';
import 'package:naviwealth/core/perf/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/perf_diagnostics_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

FrameTiming _frame({
  required int vsyncStartUs,
  required int totalUs,
  int? buildUs,
  int? rasterUs,
}) {
  final build = buildUs ?? totalUs ~/ 3;
  final raster = rasterUs ?? totalUs ~/ 3;
  return FrameTiming(
    vsyncStart: vsyncStartUs,
    buildStart: vsyncStartUs,
    buildFinish: vsyncStartUs + build,
    rasterStart: vsyncStartUs + totalUs - raster,
    rasterFinish: vsyncStartUs + totalUs,
    rasterFinishWallTime: vsyncStartUs + totalUs,
    frameNumber: vsyncStartUs ~/ 16000,
  );
}

void main() {
  testWidgets('renders frame timing diagnostics from the collector', (
    tester,
  ) async {
    final collector = FrameTimingCollector(frameBudgetUs: 16000);
    collector.ingest([
      _frame(vsyncStartUs: 0, totalUs: 8000, buildUs: 2000, rasterUs: 3000),
      _frame(
        vsyncStartUs: 16000,
        totalUs: 12000,
        buildUs: 4000,
        rasterUs: 5000,
      ),
      _frame(
        vsyncStartUs: 32000,
        totalUs: 24000,
        buildUs: 9000,
        rasterUs: 10000,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [frameTimingCollectorProvider.overrideWithValue(collector)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PerfDiagnosticsPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Recent frames'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Jank frames'), findsOneWidget);
    expect(find.text('1 / 33.3%'), findsOneWidget);
    expect(find.text('Frame timing'), findsOneWidget);
    expect(find.text('Total p95'), findsOneWidget);
    expect(find.text('22.8 ms'), findsOneWidget);
    expect(find.text('Raster p95'), findsOneWidget);
  });

  testWidgets('copies privacy-safe performance evidence', (tester) async {
    final collector = FrameTimingCollector(frameBudgetUs: 16000);
    collector.ingest([
      _frame(vsyncStartUs: 0, totalUs: 8000),
      _frame(vsyncStartUs: 16000, totalUs: 12000),
    ]);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [frameTimingCollectorProvider.overrideWithValue(collector)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PerfDiagnosticsPage(),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Copy performance evidence'));
    await tester.pump();

    expect(copiedText, isNotNull);
    final report = jsonDecode(copiedText!) as Map<String, Object?>;
    expect(report['schema_version'], 1);
    expect(report['aggregate'], containsPair('status', 'insufficientData'));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
