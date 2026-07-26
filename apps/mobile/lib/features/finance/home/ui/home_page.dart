import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_routes.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activation/ui/finance_activation_card.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_calendar_card.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/inbox/ui/financial_inbox_card.dart';
import 'package:naviwealth/features/finance/runway/ui/money_runway_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/dashboard_models.dart';
import 'activity_timeline_preview.dart';
import 'currency_mismatch_banner.dart';
import 'home_greeting_header.dart';
import 'home_section.dart';

part 'home_dashboard_body.dart';
part 'home_net_worth_header.dart';
part 'home_quick_actions.dart';

final _financeAmountsHiddenProvider = StateProvider<bool>((ref) => false);

/// FinanceOS Today brief.
///
/// Today owns current context and immediate actions: net-worth pulse (no
/// full trend chart), one agent signal, recent activity, and a compact
/// cash-flow card. Trends and allocation live on Wealth.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ShellCanvasScaffold(
      // The home cockpit owns its hero greeting; we drop the static
      // "Overview" page title in favour of a personalized status line
      // rendered inside [HomeGreetingHeader]. ShellCanvasScaffold keeps
      // this headerless tab root inside the shared shell contract while
      // [ShellActionRow] injects the compact global chrome from the hero.
      childPad: false,
      // Unmount live dashboard watches while another finance tab is
      // visible so holdings / agent / activity streams can pause.
      child: ShellTabPause(
        routePath: FinanceRoutes.home,
        placeholder: HomeSkeleton(),
        child: _HomeLiveBody(),
      ),
    );
  }
}

class _HomeLiveBody extends ConsumerWidget {
  const _HomeLiveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return PageSkeletonShell<DashboardSnapshot>(
      skeleton: const HomeSkeleton(),
      isLoading: snapshotAsync.isLoading && !snapshotAsync.hasValue,
      child: SafeArea(
        bottom: false,
        child: snapshotAsync.when(
          loading: () => const HomeSkeleton(),
          error: (e, st) => kDefaultError(
            context,
            e,
            st,
            onRetry: () => ref.invalidate(dashboardSnapshotProvider),
          ),
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
    );
  }
}
