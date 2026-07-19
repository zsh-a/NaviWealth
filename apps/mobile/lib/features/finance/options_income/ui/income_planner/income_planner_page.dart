import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../application/scan_controller.dart';
import '../../application/scan_orchestrator.dart' show ScanResult;
import '../../data/options_opportunity_cache_repository.dart';
import '../../data/providers.dart';
import '../../domain/approved_underlying.dart';
import '../../domain/option_contract.dart';
import '../../domain/options_opportunity.dart';
import '../../domain/options_strategy_profile.dart';
import '../approved_underlying_form_sheet.dart';
import '../income_planner_labels.dart';
import '../occ_disclosure_sheet.dart';
import '../opportunity_detail_sheet.dart';
import '../strategy_profile_sheet.dart';
import '../trade_journal_sheet.dart';

part 'approved.dart';
part 'body.dart';
part 'journal.dart';
part 'opportunities.dart';
part 'shared.dart';
part 'states.dart';

/// Top-level Income Planner page (`docs/domains/options-income.md` section 9).
class IncomePlannerPage extends ConsumerWidget {
  const IncomePlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const _UnsupportedOnWebPage();
    }
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(optionsStrategyProfileProvider);
    final acked = profileAsync.value?.hasAcknowledgedRiskDisclosure ?? false;
    final AppHeaderAction? settingsAction = acked
        ? AppHeaderAction(
            semanticsLabel: l10n.incomePlannerPreferencesAction,
            icon: const Icon(FLucideIcons.slidersHorizontal),
            onPress: () => showStrategyProfileSheet(context),
          )
        : null;
    return AppPageScaffold(
      title: l10n.incomePlannerTitle,
      actions: [?settingsAction],
      childPad: false,
      child: profileAsync.when(
        loading: () => const _LoadingState(),
        error: (e, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: '$e',
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(optionsStrategyProfileProvider),
        ),
        data: (profile) {
          if (profile == null || !profile.hasAcknowledgedRiskDisclosure) {
            return const _StartState();
          }
          return _ConfiguredBody(profile: profile);
        },
      ),
    );
  }
}
