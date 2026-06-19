import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/tool_invocation_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _surface = Size(360, 760);
const _captureKey = Key('ai-semantic-vision-capture');
const _headerKey = Key('tool-invocation-card-header');

ToolInvocation _inv(String name, Object? output) => ToolInvocation(
  id: 't',
  name: name,
  input: const <String, Object?>{},
  output: output,
);

Future<void> _expandCardAt(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(_headerKey).at(index));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Directory? _artifactDir() {
  final outDir = Platform.environment['AI_SEMANTIC_SCREENSHOT_DIR'];
  if (outDir == null || outDir.isEmpty) return null;

  final dir = Directory(outDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

void _writeManifest(Directory dir) {
  final sep = dir.path.endsWith(Platform.pathSeparator)
      ? ''
      : Platform.pathSeparator;
  final manifest = File('${dir.path}${sep}manifest.json');
  const visibleFacts = <String>[
    '当前净资产',
    'stock',
    'cash',
    '可用支付账户',
    'Daily Checking',
    'Wallet Cash',
  ];
  manifest.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'surface': 'ai_tool_invocation_cards.semantic_surrogate',
      'viewport': {
        'logical_width': 360,
        'logical_height': 760,
        'pixel_ratio': 1,
      },
      'screenshots': [
        {
          'path': 'ai_semantic_surfaces_phone.png',
          'description':
              'Expanded AI tool cards for net worth, asset allocation, and payment accounts at phone width.',
          'expected_visible_facts': visibleFacts,
        },
      ],
      'vision_prompt':
          'Confirm that net worth, allocation buckets, and account list are visible with no overlap, truncation, or unreadable text.',
    }),
  );
}

void main() {
  testWidgets('writes AI semantic vision screenshot artifact', (tester) async {
    final dir = _artifactDir();
    if (dir == null) {
      markTestSkipped('AI_SEMANTIC_SCREENSHOT_DIR is not set.');
      return;
    }

    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true, size: _surface),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                width: _surface.width,
                height: _surface.height,
                child: SingleChildScrollView(
                  child: Column(
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
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await _expandCardAt(tester, i);
    }

    expect(tester.takeException(), isNull);
    expect(find.text('当前净资产'), findsOneWidget);
    expect(find.text('stock'), findsOneWidget);
    expect(find.text('cash'), findsOneWidget);
    expect(find.text('可用支付账户'), findsOneWidget);
    expect(find.text('Daily Checking'), findsOneWidget);
    expect(find.text('Wallet Cash'), findsOneWidget);

    final sep = dir.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    final previousComparator = goldenFileComparator;
    goldenFileComparator = LocalFileComparator(
      Uri.file('${dir.path}${sep}ai_semantic_vision_artifact_test.dart'),
    );
    try {
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('ai_semantic_surfaces_phone.png'),
      );
    } finally {
      goldenFileComparator = previousComparator;
    }
    _writeManifest(dir);
  }, tags: 'golden');
}
