import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';

/// Structural / source-path checks for the shipped scan wiring.
///
/// The pure mapper is covered by [portfolio_guardrail_candidates_test.dart].
/// This file asserts the production scan provider and inbox UI actually
/// reference the new kinds, routes, and mapper — so a refactor cannot drop
/// the guardrail loop while unit tests of pure helpers still pass.
void main() {
  final repoRoot = _findRepoRoot();
  final scanProvider = File(
    '$repoRoot/apps/mobile/lib/features/finance/inbox/data/financial_inbox_providers.dart',
  );
  final inboxPage = File(
    '$repoRoot/apps/mobile/lib/features/finance/inbox/ui/financial_inbox_page.dart',
  );
  final mapper = File(
    '$repoRoot/apps/mobile/lib/features/finance/inbox/domain/portfolio_guardrail_candidates.dart',
  );

  test('scan provider wires concentration alerts and rebalance plan', () {
    final source = scanProvider.readAsStringSync();
    expect(source, contains('concentrationAlertsProvider'));
    expect(source, contains('rebalancePlanProvider'));
    expect(source, contains('fromConcentrationAlerts'));
    expect(source, contains('fromRebalancePlan'));
    expect(source, contains('PortfolioGuardrailCandidates'));
  });

  test('inbox page presents both new kinds', () {
    final source = inboxPage.readAsStringSync();
    expect(source, contains('FinancialInboxKind.concentrationRisk'));
    expect(source, contains('FinancialInboxKind.rebalanceDrift'));
    expect(source, contains('financialInboxConcentrationTitle'));
    expect(source, contains('financialInboxRebalanceTitle'));
  });

  test('mapper routes use portfolio analytics and rebalance plan surfaces', () {
    final source = mapper.readAsStringSync();
    expect(source, contains('FinanceRoutes.wealthPortfolio'));
    expect(source, contains('FinanceRoutes.planRebalance'));
    expect(source, contains("sourceKey: rebalanceDriftSourceKey"));
    expect(source, contains('concentration:'));
  });

  test(
    'enum includes concentration and rebalance kinds for byName persistence',
    () {
      expect(
        FinancialInboxKind.values.map((k) => k.name),
        containsAll(['concentrationRisk', 'rebalanceDrift']),
      );
      expect(
        FinancialInboxKind.values.byName('concentrationRisk'),
        FinancialInboxKind.concentrationRisk,
      );
      expect(
        FinancialInboxKind.values.byName('rebalanceDrift'),
        FinancialInboxKind.rebalanceDrift,
      );
    },
  );

  test(
    'no curated model portfolio defaults in rebalance or inbox product code',
    () {
      // Scope to product surfaces that could ship a model sleeve, not incidental
      // merchant/issuer strings in statement parsers or expense taxonomy.
      final paths = [
        '$repoRoot/apps/mobile/lib/features/finance/rebalance',
        '$repoRoot/apps/mobile/lib/features/finance/inbox',
        '$repoRoot/apps/mobile/lib/features/finance/analytics',
      ];
      final forbidden = [
        '中国移动',
        '长江电力',
        '招商银行',
        '美的集团',
        '宁沪高速',
        '中国神华',
        '万洲国际',
        '核心红利组合',
        '600941',
        '600900',
        '600036',
        '000333',
        '600377',
        '601088',
        '00288',
      ];
      final offenders = <String>[];
      for (final root in paths) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final file in dir.listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          final text = file.readAsStringSync();
          for (final token in forbidden) {
            if (text.contains(token)) {
              offenders.add('${file.path}: $token');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    },
  );
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    final agents = File('${dir.path}/Agents.md');
    final mobile = Directory('${dir.path}/apps/mobile');
    if (agents.existsSync() && mobile.existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail(
        'Could not locate NaviWealth repo root from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}
