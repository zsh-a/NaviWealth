import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
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
    return AppPageScaffold(
      title: l10n.expenseReportAppBarTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.list),
          onPress: () => context.go(AppRoutes.activityExpenses),
        ),
      ],
      childPad: false,
      child: reportAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => Center(child: Text(l10n.expenseReportLoadError('$e'))),
        data: (report) => ExpenseReportBody(report: report),
      ),
    );
  }
}
