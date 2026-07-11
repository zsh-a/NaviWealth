import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_calendar_card.dart';
import 'package:naviwealth/features/finance/cashflow/ui/passive_income_card.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/dashboard_models.dart';
import 'activity_timeline_preview.dart';
import 'allocation_summary.dart';
import 'currency_mismatch_banner.dart';
import 'home_greeting_header.dart';
import 'home_section.dart';
import 'trend_card.dart';

part 'home_dashboard_body.dart';
part 'home_net_worth_header.dart';
part 'home_quick_actions.dart';

final _valuationStatusTickerProvider = StreamProvider.autoDispose<DateTime>((
  ref,
) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 15),
    (_) => DateTime.now(),
  );
});

final _financeAmountsHiddenProvider = StateProvider<bool>((ref) => false);

/// Home cockpit.
///
/// One-column scroll: Net Worth Hero → AI Insight Feed → Allocation
/// Summary → Recent Activity preview → Trend chart. The heavy Sankey
/// allocation moved out of the home (it now lives on the dedicated
/// detail surface inside the Accounts hub) so the home reads more like
/// a calm "financial cockpit" than a trading terminal.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now().toUtc();
    ref.watch(
      recurringMaterialiseDueProvider(
        DateTime.utc(today.year, today.month, today.day),
      ),
    );
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return ShellCanvasScaffold(
      // The home cockpit owns its hero greeting; we drop the static
      // "Overview" page title in favour of a personalized status line
      // rendered inside [HomeGreetingHeader]. ShellCanvasScaffold keeps
      // this headerless tab root inside the shared shell contract while
      // [ShellActionRow] injects the compact global chrome from the hero.
      childPad: false,
      child: PageSkeletonShell<DashboardSnapshot>(
        skeleton: const HomeSkeleton(),
        isLoading: snapshotAsync.isLoading && !snapshotAsync.hasValue,
        child: SafeArea(
          bottom: false,
          child: snapshotAsync.when(
            loading: () => const HomeSkeleton(),
            error: (e, st) => _ErrorBody(error: e),
            data: (snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CurrencyMismatchNotice(
                  mismatches: snapshot.currencyMismatches,
                  baseCurrency: snapshot.baseCurrency,
                ),
                Expanded(child: _DashboardBody(snapshot: snapshot)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState.error(
      title: userSafeErrorMessage(
        context,
        error,
        operation: 'load dashboard snapshot',
      ),
      retryLabel: l10n.commonRetry,
      onRetry: () => ref.invalidate(dashboardSnapshotProvider),
    );
  }
}
