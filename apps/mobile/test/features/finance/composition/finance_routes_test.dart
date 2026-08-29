import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/composition/finance_routes.dart';

void main() {
  test('legacy journal route redirects to the canonical Activity ledger', () {
    final shell = financeShellRoute();
    final activity = shell.branches[1].routes.single as GoRoute;
    final journal = activity.routes.whereType<GoRoute>().singleWhere(
      (route) => route.path == 'journal',
    );

    expect(journal.name, FinanceRouteNames.journalEntries);
    expect(journal.redirect, isNotNull);
    expect(journal.builder, isNull);
  });
}
