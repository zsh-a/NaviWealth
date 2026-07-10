import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/cash_flow_providers.dart';
import '../data/recurring_transaction_providers.dart';
import '../domain/cash_flow_aggregator.dart';
import '../domain/cash_flow_kind.dart';

part 'cashflow/charts.dart';
part 'cashflow/content.dart';
part 'cashflow/money.dart';
part 'cashflow/states.dart';
part 'cashflow/view_model.dart';

class CashFlowPage extends ConsumerStatefulWidget {
  const CashFlowPage({super.key});

  @override
  ConsumerState<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends ConsumerState<CashFlowPage> {
  CashFlowPeriod _period = CashFlowPeriod.month;
  bool _hydratedFromUrl = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(
        recurringMaterialiseDueProvider(DateTime.now().toUtc()).future,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    _period = _periodFromUri(
      GoRouter.of(context).routeInformationProvider.value.uri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final request = CashFlowSummaryRequest(period: _period);
    final summaryAsync = ref.watch(cashFlowSummaryProvider(request));

    return AppPageScaffold(
      title: l10n.cashFlowTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.calendarClock),
          onPress: () => context.push(FinanceRoutes.cashflowRecurring),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.wallet),
          onPress: () => context.push(FinanceRoutes.cashflowDividends),
        ),
      ],
      childPad: false,
      child: PageSkeletonShell<CashFlowSummary>(
        skeleton: const CashFlowSkeleton(),
        isLoading: summaryAsync.isLoading,
        child: summaryAsync.when(
          loading: () => const CashFlowSkeleton(),
          error: (error, _) => _LoadError(
            message: userSafeErrorMessage(context, error),
            onRetry: () => ref.invalidate(cashFlowSummaryProvider(request)),
          ),
          data: (summary) => summary.buckets.isEmpty
              ? const _EmptyState()
              : _CashFlowContent(
                  period: _period,
                  summary: summary,
                  formatter: formatter,
                  now: ref.watch(cashFlowNowProvider),
                  onPeriodChanged: _changePeriod,
                ),
        ),
      ),
    );
  }

  void _changePeriod(CashFlowPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    context.go('${FinanceRoutes.cashflow}?period=${period.name}');
  }
}
