import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/cash_flow_providers.dart';
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

String cashFlowActivityRoute({
  required CashFlowPeriod period,
  required DateTime anchor,
  Set<ActivityKind> kinds = const <ActivityKind>{},
  Set<String> accountIds = const <String>{},
}) {
  final date = anchor.toUtc();
  final (start, end) = switch (period) {
    CashFlowPeriod.month => (
      DateTime.utc(date.year, date.month),
      DateTime.utc(date.year, date.month + 1),
    ),
    CashFlowPeriod.quarter => (
      DateTime.utc(date.year, ((date.month - 1) ~/ 3) * 3 + 1),
      DateTime.utc(date.year, ((date.month - 1) ~/ 3) * 3 + 4),
    ),
    CashFlowPeriod.year => (
      DateTime.utc(date.year),
      DateTime.utc(date.year + 1),
    ),
  };
  final query = ActivityFeedQuery(
    dateRange: DateTimeRange(start: start, end: end),
    accountIds: accountIds,
    kinds: kinds,
  );
  return Uri(
    path: FinanceRoutes.activity,
    queryParameters: query.toQueryParameters(),
  ).toString();
}

class _CashFlowPageState extends ConsumerState<CashFlowPage> {
  CashFlowPeriod _period = CashFlowPeriod.month;
  late DateTime _anchor;
  bool _hydratedFromUrl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    final now = ref.read(cashFlowNowProvider);
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    _period = _periodFromUri(uri);
    _anchor = _anchorFromUri(uri, fallback: now);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = context.formatters(ref);
    final now = ref.watch(cashFlowNowProvider);
    final request = CashFlowSummaryRequest(period: _period);
    final summaryAsync = ref.watch(cashFlowSummaryProvider(request));

    return AppPageScaffold(
      title: l10n.cashFlowTitle,
      actions: [
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.navActivity),
            child: const Icon(FLucideIcons.list),
          ),
          semanticsLabel: l10n.navActivity,
          onPress: () => context.go(FinanceRoutes.activity),
        ),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
            AppAdaptiveAction(
              icon: FLucideIcons.calendarClock,
              title: l10n.recurringListTitle,
              onPress: () => context.push(FinanceRoutes.cashflowRecurring),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.wallet,
              title: l10n.dividendCenterTitle,
              onPress: () => context.push(FinanceRoutes.cashflowDividends),
            ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => AppHeaderAction(
            semanticsLabel: l10n.shellMoreActions,
            icon: const Icon(FLucideIcons.ellipsis),
            focusNode: focusNode,
            onPress: openMenu,
          ),
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
                  anchor: _anchor,
                  now: now,
                  onPeriodChanged: _changePeriod,
                  onAnchorChanged: _changeAnchor,
                ),
        ),
      ),
    );
  }

  void _changePeriod(CashFlowPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _replaceLocation();
  }

  void _changeAnchor(DateTime anchor) {
    setState(() => _anchor = anchor.toUtc());
    _replaceLocation();
  }

  void _replaceLocation() {
    final anchor = _anchor.toUtc();
    final date =
        '${anchor.year.toString().padLeft(4, '0')}-'
        '${anchor.month.toString().padLeft(2, '0')}-'
        '${anchor.day.toString().padLeft(2, '0')}';
    context.replace(
      Uri(
        path: FinanceRoutes.cashflow,
        queryParameters: {'period': _period.name, 'anchor': date},
      ).toString(),
    );
  }
}
