import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_routes.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_results_panel.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activation/data/finance_activation_providers.dart';
import 'package:naviwealth/features/finance/activation/data/finance_activation_store.dart';
import 'package:naviwealth/features/finance/activation/ui/finance_activation_card.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/composition/finance_domain_shell.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/finance_amount_privacy_preference.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_inbox_providers.dart';
import 'package:naviwealth/features/finance/inbox/ui/financial_inbox_card.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';
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

/// FinanceOS Today brief.
///
/// Today owns current context and immediate actions: net-worth pulse (no
/// full trend chart), actionable signals, and recent activity. Detailed cash
/// flow, trends, and allocation stay in their dedicated workspaces.
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
    final snapshot = snapshotAsync.value;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot != null)
            ValuationTrustNotice(snapshot: snapshot, showHealthy: false),
          Expanded(child: _DashboardBody(snapshotAsync: snapshotAsync)),
        ],
      ),
    );
  }
}
