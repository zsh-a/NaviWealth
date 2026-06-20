import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('testing infrastructure contracts', () {
    final appRoot = _appRoot();

    test('non-golden tests have a package-wide flutter_test_config', () {
      final config = File('${appRoot.path}/test/flutter_test_config.dart');

      expect(config.existsSync(), isTrue);
      final text = config.readAsStringSync();
      expect(text, contains('TestWidgetsFlutterBinding.ensureInitialized'));
      expect(text, isNot(contains('package:golden_toolkit')));
    });

    test('known-failing allowlist remains retired', () {
      expect(
        File('${appRoot.path}/tool/known-failing-tests.txt').existsSync(),
        isFalse,
      );
      expect(
        File('${appRoot.path}/tool/check-known-failing-tests.sh').existsSync(),
        isFalse,
      );
    });

    test('AI trace waterfall regression tests stay active', () {
      final file = File(
        '${appRoot.path}/test/features/settings/ai_trace_waterfall_test.dart',
      );

      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(_countTestCases([file]), greaterThanOrEqualTo(5));
      expect(text, isNot(contains('skip:')));
      expect(text, isNot(contains('pumpAndSettle')));
    });

    test('critical user flows stay covered outside the sync E2E test', () {
      const flowFiles = <String>[
        'test/flow/add_account_flow_test.dart',
        'test/flow/add_transaction_flow_test.dart',
        'test/flow/transfer_flow_test.dart',
        'test/flow/budget_flow_test.dart',
        'test/flow/net_worth_flow_test.dart',
        'test/flow/portfolio_analysis_flow_test.dart',
        'test/flow/rebalance_flow_test.dart',
        'test/flow/options_income_flow_test.dart',
        'test/flow/ai_chat_flow_test.dart',
      ];

      for (final path in flowFiles) {
        final file = File('${appRoot.path}/$path');
        expect(file.existsSync(), isTrue, reason: '$path should exist');
        expect(
          file.readAsStringSync(),
          contains("tags: 'flow'"),
          reason: '$path should be tagged as a flow test',
        );
      }
    });

    test('E2E coverage spans sync protocol and finance ledger bundles', () {
      const e2eFiles = <String>[
        'test/e2e/sync_e2e_test.dart',
        'test/e2e/finance_ledger_e2e_test.dart',
      ];

      for (final path in e2eFiles) {
        final file = File('${appRoot.path}/$path');
        expect(file.existsSync(), isTrue, reason: '$path should exist');
        expect(
          file.readAsStringSync(),
          contains('SyncCluster'),
          reason: '$path should exercise the virtual multi-device harness',
        );
      }
    });

    test('review-priority modules keep direct test coverage', () {
      const requiredCoverage =
          <String, ({String testPath, int minTestFiles, int minTestCases})>{
            'core/background': (
              testPath: 'test/core/background',
              minTestFiles: 2,
              minTestCases: 4,
            ),
            'core/notifications': (
              testPath: 'test/core/notifications',
              minTestFiles: 2,
              minTestCases: 7,
            ),
            'core/persistence': (
              testPath: 'test/core/persistence',
              minTestFiles: 3,
              minTestCases: 40,
            ),
            'core/security': (
              testPath: 'test/core/security',
              minTestFiles: 2,
              minTestCases: 5,
            ),
            'features/plan': (
              testPath: 'test/features/plan',
              minTestFiles: 1,
              minTestCases: 7,
            ),
            'features/assets': (
              testPath: 'test/features/assets',
              minTestFiles: 7,
              minTestCases: 30,
            ),
            'features/options_income': (
              testPath: 'test/features/options_income',
              minTestFiles: 8,
              minTestCases: 50,
            ),
            'features/rebalance': (
              testPath: 'test/features/rebalance',
              minTestFiles: 4,
              minTestCases: 15,
            ),
          };

      for (final entry in requiredCoverage.entries) {
        final sourceDir = Directory('${appRoot.path}/lib/${entry.key}');
        final testDir = Directory('${appRoot.path}/${entry.value.testPath}');
        final testFiles = _testFiles(testDir);
        final testCaseCount = _countTestCases(testFiles);
        expect(
          sourceDir.existsSync(),
          isTrue,
          reason: '${entry.key} source directory should exist',
        );
        expect(
          testFiles.length,
          greaterThanOrEqualTo(entry.value.minTestFiles),
          reason:
              '${entry.key} should keep at least '
              '${entry.value.minTestFiles} '
              'direct tests in ${entry.value.testPath}',
        );
        expect(
          testCaseCount,
          greaterThanOrEqualTo(entry.value.minTestCases),
          reason:
              '${entry.key} should keep at least '
              '${entry.value.minTestCases} direct test cases in '
              '${entry.value.testPath}; empty shell files do not count.',
        );
      }
    });

    test('review-priority module tests span their risky slices', () {
      const requiredFiles = <String, int>{
        // Assets: keep provider, physical asset, depreciation, and UI list
        // model behavior covered directly.
        'test/features/assets/assets_page_securities_test.dart': 2,
        'test/features/assets/data/asset_detail_providers_test.dart': 4,
        'test/features/assets/data/deposit_maturity_insight_provider_test.dart':
            2,
        'test/features/assets/physical/data/physical_asset_repository_test.dart':
            4,
        'test/features/assets/physical/domain/vehicle_depreciation_test.dart':
            3,
        'test/features/assets/ui/assets_list_models_test.dart': 2,

        // Options income: scanner/application, repositories, scoring, AI, and
        // presentation should not collapse back into one broad smoke file.
        'test/features/options_income/application/scan_inputs_bridge_test.dart':
            3,
        'test/features/options_income/application/scan_orchestrator_test.dart':
            3,
        'test/features/options_income/data/options_income_repositories_test.dart':
            6,
        'test/features/options_income/data/options_opportunity_cache_repository_test.dart':
            3,
        'test/features/options_income/domain/opportunity_scorer_test.dart': 8,
        'test/features/options_income/domain/wheel_lifecycle_test.dart': 4,
        'test/features/options_income/ai_tools/get_wheel_lifecycle_tool_test.dart':
            3,
        'test/features/options_income/presentation/wheel_lifecycle_page_test.dart':
            1,

        // Rebalance: engine behavior, insight provider, and both editing /
        // execution surfaces need separate regression coverage.
        'test/features/rebalance/domain/rebalance_engine_test.dart': 5,
        'test/features/rebalance/data/rebalance_drift_insight_provider_test.dart':
            2,
        'test/features/rebalance/rebalance_execution_sheet_test.dart': 4,
        'test/features/rebalance/target_allocation_editor_sheet_test.dart': 4,

        // Persistence: schema verification alone is not enough; converters
        // and app database behavior must stay directly covered.
        'test/core/persistence/schema_verification_test.dart': 1,
        'test/core/persistence/converters_test.dart': 3,
        'test/core/persistence/app_database_behavior_test.dart': 17,
      };

      for (final entry in requiredFiles.entries) {
        final file = File('${appRoot.path}/${entry.key}');
        expect(file.existsSync(), isTrue, reason: '${entry.key} should exist');
        expect(
          _countTestCases([file]),
          greaterThanOrEqualTo(entry.value),
          reason:
              '${entry.key} should keep at least ${entry.value} concrete '
              'test cases; empty shell files do not count.',
        );
      }
    });

    test('golden harness uses deterministic fixed-frame pumping', () {
      final setup = File('${appRoot.path}/test/golden/_golden_setup.dart');

      expect(setup.existsSync(), isTrue);
      final text = setup.readAsStringSync();
      expect(text, contains('loadGoldenFonts'));
      expect(text, contains('_verifyGoldenFontAssets'));
      expect(text, contains('inter-regular.woff2'));
      expect(text, contains('outfit-bold.woff2'));
      expect(text, contains('app-cn-base.woff2'));
      expect(
        text,
        isNot(matches(RegExp(r'\bawait\s+tester\.pumpAndSettle\('))),
      );

      final goldenDartFiles = Directory('${appRoot.path}/test/golden')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final pumpAndSettle = RegExp(r'\bawait\s+tester\.pumpAndSettle\(');
      for (final file in goldenDartFiles) {
        expect(
          file.readAsStringSync(),
          isNot(matches(pumpAndSettle)),
          reason:
              '${file.path} should use deterministic bounded pumps for '
              'goldens instead of pumpAndSettle.',
        );
      }
    });

    test('golden comparison policy stays Linux-pinned and update-friendly', () {
      final config = File(
        '${appRoot.path}/test/golden/flutter_test_config.dart',
      );

      expect(config.existsSync(), isTrue);
      final text = config.readAsStringSync();
      expect(text, contains('skipGoldenAssertion'));
      expect(text, contains('Platform.isLinux'));
      expect(text, contains('autoUpdateGoldenFiles'));
      expect(text, contains('enableRealShadows: true'));
    });

    test('golden inventory stays documented', () {
      final goldenDir = Directory('${appRoot.path}/test/golden');
      final goldenFiles = goldenDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('_golden_test.dart'))
          .toList(growable: false);
      final pngFiles = Directory('${goldenDir.path}/goldens')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .toList(growable: false);

      expect(goldenFiles, hasLength(17));
      expect(pngFiles, hasLength(50));

      final repoRoot = appRoot.parent.parent;
      final docs = File('${repoRoot.path}/docs/visual-baseline/README.md');
      expect(docs.existsSync(), isTrue);
      final text = docs.readAsStringSync();
      expect(text, contains('17 test files'));
      expect(text, contains('50 PNG baselines'));
      expect(text, contains('sync_status_page_golden_test.dart'));
    });
  });
}

List<File> _testFiles(Directory root) {
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('_test.dart'))
      .where((file) => !file.path.endsWith('/test_database.dart'))
      .toList(growable: false);
}

int _countTestCases(Iterable<File> files) {
  final pattern = RegExp(r'\btest(?:Widgets)?\s*\(');
  return files.fold<int>(
    0,
    (count, file) => count + pattern.allMatches(file.readAsStringSync()).length,
  );
}

Directory _appRoot() {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError(
    'Unable to locate apps/mobile root from ${Directory.current}',
  );
}
