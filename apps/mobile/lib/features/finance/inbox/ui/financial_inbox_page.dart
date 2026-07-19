import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/financial_inbox_providers.dart';
import '../domain/financial_inbox.dart';

class FinancialInboxPage extends ConsumerWidget {
  const FinancialInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(financialInboxProvider);
    return AppPageScaffold(
      title: l10n.financialInboxTitle,
      childPad: false,
      child: items.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: '$error',
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(financialInboxProvider),
        ),
        data: (rows) => rows.isEmpty
            ? AppEmptyState(
                icon: FLucideIcons.circleCheckBig,
                title: l10n.financialInboxEmptyTitle,
                message: l10n.financialInboxEmptyBody,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.s16),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.s10),
                itemBuilder: (context, index) => _InboxRow(item: rows[index]),
              ),
      ),
    );
  }
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({required this.item});

  final FinancialInboxItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, body) = switch (item.kind) {
      FinancialInboxKind.importReview => (
        FLucideIcons.fileCheck,
        l10n.financialInboxImportTitle(item.count),
        l10n.financialInboxImportBody,
      ),
      FinancialInboxKind.runwayRisk => (
        FLucideIcons.calendarClock,
        l10n.financialInboxRunwayTitle,
        l10n.financialInboxRunwayBody,
      ),
      FinancialInboxKind.missingExchangeRate => (
        FLucideIcons.badgeDollarSign,
        l10n.financialInboxFxTitle(item.count),
        l10n.financialInboxFxBody,
      ),
    };
    return SoftCard.raised(
      borderless: true,
      onPress: () => context.push(item.route),
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        children: [
          Icon(icon, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(body, style: context.captionStyle),
              ],
            ),
          ),
          Column(
            children: [
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () async {
                  final repository = await ref.read(
                    financialSignalRepositoryProvider.future,
                  );
                  await repository.resolve(item.id, now: DateTime.now());
                  final remaining = await repository.listVisible(
                    now: DateTime.now(),
                  );
                  if (remaining.isEmpty) {
                    await ref
                        .read(productMetricsProvider.notifier)
                        .record(
                          ProductFunnelEvent.financialInboxCleared,
                          success: true,
                        );
                  }
                  ref.invalidate(financialInboxProvider);
                },
                child: Text(l10n.financialInboxResolve),
              ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () async {
                  final now = DateTime.now();
                  final repository = await ref.read(
                    financialSignalRepositoryProvider.future,
                  );
                  await repository.snooze(
                    item.id,
                    until: now.add(const Duration(days: 7)),
                    now: now,
                  );
                  ref.invalidate(financialInboxProvider);
                },
                child: Text(l10n.financialInboxSnooze),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
