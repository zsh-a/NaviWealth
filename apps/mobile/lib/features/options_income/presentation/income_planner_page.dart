import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../domain/values/asset_market.dart';
import '../data/providers.dart';
import '../domain/approved_underlying.dart';
import '../domain/options_strategy_profile.dart';
import 'approved_underlying_form_sheet.dart';
import 'income_planner_strings.dart';
import 'occ_disclosure_sheet.dart';
import 'strategy_profile_sheet.dart';

/// Top-level Income Planner page (`docs/options-income.md` §9).
///
/// P0 surface:
///   * OCC ODD disclosure gate on first run
///   * Strategy profile read/edit
///   * Approved underlyings CRUD
///   * Opportunities section is a P1 placeholder (scanner not wired yet)
///
/// Web build: returns an empty page. Income Planner is mobile-only,
/// matching the AI device-only invariant in `docs/ai-architecture.md`.
class IncomePlannerPage extends ConsumerWidget {
  const IncomePlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const _UnsupportedOnWebPage();
    }
    final profileAsync = ref.watch(optionsStrategyProfileProvider);
    final acked =
        profileAsync.value?.hasAcknowledgedRiskDisclosure ?? false;
    final FHeaderAction? settingsAction = acked
        ? FHeaderAction(
            icon: const Icon(Icons.tune),
            onPress: () => showStrategyProfileSheet(context),
          )
        : null;
    return FScaffold(
      header: FHeader.nested(
        title: const Text(IncomePlannerStrings.pageTitle),
        suffixes: [?settingsAction],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: profileAsync.when(
          loading: () => const _LoadingState(),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (profile) {
            if (profile == null ||
                !profile.hasAcknowledgedRiskDisclosure) {
              return const _StartState();
            }
            return _ConfiguredBody(profile: profile);
          },
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Text(
        message,
        style: TextStyle(color: context.theme.colors.destructive),
      ),
    );
  }
}

class _UnsupportedOnWebPage extends StatelessWidget {
  const _UnsupportedOnWebPage();

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader.nested(title: Text(IncomePlannerStrings.pageTitle)),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.s24),
        child: Text(
          'Income Planner is only available on mobile.',
        ),
      ),
    );
  }
}

class _StartState extends ConsumerWidget {
  const _StartState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.candlestick_chart_outlined,
              size: 48,
              color: colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              IncomePlannerStrings.startTitle,
              style: context.theme.typography.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              IncomePlannerStrings.startBody,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            FButton(
              onPress: () => showOccDisclosureSheet(context),
              child: const Text(IncomePlannerStrings.startCta),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredBody extends ConsumerWidget {
  const _ConfiguredBody({required this.profile});

  final OptionsStrategyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvedAsync = ref.watch(approvedUnderlyingsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        _SectionHeader(
          title: IncomePlannerStrings.approvedSectionTitle,
          trailing: FButton(
            variant: FButtonVariant.outline,
            onPress: () => showApprovedUnderlyingSheet(context),
            child: const Text(IncomePlannerStrings.addApprovedCta),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        approvedAsync.when(
          loading: () => const _LoadingTile(),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (items) => items.isEmpty
              ? const _ApprovedEmpty()
              : _ApprovedList(items: items),
        ),
        const SizedBox(height: AppSpacing.s24),
        const _SectionHeader(
          title: IncomePlannerStrings.opportunitiesSectionTitle,
        ),
        const SizedBox(height: AppSpacing.s8),
        const _OpportunitiesPlaceholder(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.theme.typography.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _ApprovedEmpty extends StatelessWidget {
  const _ApprovedEmpty();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              IncomePlannerStrings.noApprovedTitle,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              IncomePlannerStrings.noApprovedBody,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedList extends StatelessWidget {
  const _ApprovedList({required this.items});

  final List<ApprovedUnderlying> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: _ApprovedTile(item: item),
          ),
      ],
    );
  }
}

class _ApprovedTile extends StatelessWidget {
  const _ApprovedTile({required this.item});

  final ApprovedUnderlying item;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard(
      child: InkWell(
        onTap: () =>
            showApprovedUnderlyingSheet(context, existing: item),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displaySymbol,
                      style: context.theme.typography.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      item.market.wire,
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              _StrategyChip(
                label: IncomePlannerStrings.profileAllowPut,
                enabled: item.allowPut,
              ),
              const SizedBox(width: AppSpacing.s6),
              _StrategyChip(
                label: IncomePlannerStrings.profileAllowCall,
                enabled: item.allowCall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled
            ? colors.primary.withValues(alpha: 0.12)
            : colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: context.theme.typography.xs.copyWith(
            color: enabled ? colors.primary : colors.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _OpportunitiesPlaceholder extends StatelessWidget {
  const _OpportunitiesPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          IncomePlannerStrings.opportunitiesEmpty,
          style: context.theme.typography.sm.copyWith(
            color: colors.mutedForeground,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
