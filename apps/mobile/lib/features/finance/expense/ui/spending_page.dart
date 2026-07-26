import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/expense_category_providers.dart';
import '../data/expense_report_providers.dart';
import 'expense_report_content.dart';

/// Consumption analysis over expense-account postings.
///
/// Transaction browsing belongs to Activity; this page only owns aggregate
/// spending metrics, trends, and category navigation.
class SpendingPage extends ConsumerWidget {
  const SpendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reportAsync = ref.watch(expenseReportProvider);
    final categoriesAsync = ref.watch(allExpenseCategoriesProvider);
    return AppPageScaffold(
      title: l10n.spendingTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.piggyBank),
          semanticsLabel: l10n.planBudgetTitle,
          onPress: () => context.push(FinanceRoutes.planBudget),
        ),
      ],
      childPad: false,
      child: reportAsync.whenOrLoading(
        context: context,
        onRetry: () => ref.invalidate(expenseReportProvider),
        data: (report) => categoriesAsync.whenOrLoading(
          context: context,
          onRetry: () => ref.invalidate(allExpenseCategoriesProvider),
          data: (categories) => SpendingBody(
            report: report,
            categoryById: {
              for (final category in categories) category.id: category,
            },
          ),
        ),
      ),
    );
  }
}
