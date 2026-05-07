import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/expense_report_providers.dart';
import 'expense_report_content.dart';

class ExpenseReportPage extends ConsumerWidget {
  const ExpenseReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reportAsync = ref.watch(expenseReportProvider);
    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.expenseReportAppBarTitle)),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.expenseReportLoadError('$e'))),
        data: (report) => ExpenseReportBody(report: report),
      ),
    );
  }
}
