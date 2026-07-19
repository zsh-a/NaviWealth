import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../data/monthly_close_providers.dart';
import '../domain/account_reconciliation.dart';
import '../domain/monthly_close.dart';

class MonthlyClosePage extends ConsumerStatefulWidget {
  const MonthlyClosePage({super.key});

  @override
  ConsumerState<MonthlyClosePage> createState() => _MonthlyClosePageState();
}

class _MonthlyClosePageState extends ConsumerState<MonthlyClosePage> {
  String? _beginRequestedFor;

  void _ensureSessionStarted({
    required String period,
    required MonthlyClose? close,
    required MonthlyCloseEvidence? evidence,
  }) {
    if (close != null || evidence == null || _beginRequestedFor == period) {
      return;
    }
    _beginRequestedFor = period;
    unawaited(_beginSession(period: period, evidence: evidence));
  }

  Future<void> _beginSession({
    required String period,
    required MonthlyCloseEvidence evidence,
  }) async {
    try {
      final repository = await ref.read(monthlyCloseRepositoryProvider.future);
      await repository.begin(
        periodMonth: period,
        evidence: evidence,
        snapshot: evidence.details,
        now: DateTime.now(),
      );
    } catch (_) {
      if (mounted && _beginRequestedFor == period) {
        setState(() => _beginRequestedFor = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(currentClosePeriodProvider);
    final closeAsync = ref.watch(currentMonthlyCloseProvider);
    final evidenceAsync = ref.watch(monthlyCloseEvidenceProvider);
    final targetsAsync = ref.watch(reconciliationTargetsProvider);
    final comparison = ref.watch(monthlyCloseComparisonProvider).value;
    _ensureSessionStarted(
      period: period,
      close: closeAsync.value,
      evidence: evidenceAsync.value,
    );
    return AppPageScaffold(
      title: l10n.monthlyCloseTitle,
      childPad: false,
      child: closeAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => _LoadError(error: error),
        data: (close) {
          if (close?.isClosed == true) {
            return _ClosedMonth(close: close!);
          }
          return evidenceAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (error, _) => _LoadError(error: error),
            data: (evidence) => ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                Text(
                  l10n.monthlyClosePeriod(period),
                  style: context.rowTitleStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(l10n.monthlyCloseIntro, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s16),
                _CloseProgress(evidence: evidence, comparison: comparison),
                const SizedBox(height: AppSpacing.s16),
                for (final step in MonthlyCloseStep.values) ...[
                  _CloseStepRow(step: step, state: evidence.states[step]!),
                  const SizedBox(height: AppSpacing.s8),
                ],
                const SizedBox(height: AppSpacing.s16),
                Text(
                  l10n.monthlyCloseReconciliationTitle,
                  style: context.rowTitleStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                targetsAsync.when(
                  loading: () => const Center(child: FCircularProgress()),
                  error: (error, _) => Text('$error'),
                  data: (targets) => Column(
                    children: [
                      for (final target in targets) ...[
                        _ReconciliationRow(target: target),
                        const SizedBox(height: AppSpacing.s8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                FButton(
                  onPress: () => _closeMonth(
                    context,
                    ref,
                    evidence: evidence,
                    period: period,
                    startedAt: close?.startedAt,
                  ),
                  child: Text(
                    evidence.isVerified
                        ? l10n.monthlyCloseComplete
                        : l10n.monthlyCloseWithException,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _closeMonth(
    BuildContext context,
    WidgetRef ref, {
    required MonthlyCloseEvidence evidence,
    required String period,
    required DateTime? startedAt,
  }) async {
    final l10n = AppLocalizations.of(context);
    String? reason;
    if (!evidence.isVerified) {
      reason = await _textPrompt(
        context,
        title: l10n.monthlyCloseExceptionTitle,
        hint: l10n.monthlyCloseExceptionHint,
      );
      if (reason == null) return;
    }
    final now = DateTime.now();
    final duration = startedAt == null
        ? Duration.zero
        : now.difference(startedAt);
    final repository = await ref.read(monthlyCloseRepositoryProvider.future);
    await repository.close(
      periodMonth: period,
      evidence: evidence,
      snapshot: <String, Object?>{
        ...evidence.details,
        'closed_at': now.toUtc().toIso8601String(),
        'close_duration_ms': duration.inMilliseconds,
      },
      overrideReason: reason,
      now: now,
    );
    await ref
        .read(productMetricsProvider.notifier)
        .record(
          ProductFunnelEvent.monthlyCloseCompleted,
          duration: duration,
          success: true,
        );
  }
}

class _CloseProgress extends StatelessWidget {
  const _CloseProgress({required this.evidence, required this.comparison});

  final MonthlyCloseEvidence evidence;
  final MonthlyCloseComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total =
        (evidence.details['reconciliation_target_count'] as num?)?.toInt() ?? 0;
    final accepted =
        (evidence.details['reconciliation_accepted_count'] as num?)?.toInt() ??
        0;
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.monthlyCloseCoverageTitle,
                  style: context.labelStyle,
                ),
              ),
              Text(
                l10n.monthlyCloseCoverageValue(accepted, total),
                style: TypographyTokens.numericBodyStrong,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          LinearProgressIndicator(value: total == 0 ? 0 : accepted / total),
          if (comparison?.hasPrevious == true) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              l10n.monthlyCloseSincePrevious(
                comparison!.newSignalKeys.length,
                comparison!.clearedSignalKeys.length,
              ),
              style: context.captionStyle,
            ),
            if (comparison!.previousDuration != null)
              Text(
                l10n.monthlyClosePreviousDuration(
                  comparison!.previousDuration!.inMinutes,
                ),
                style: context.captionStyle,
              ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends ConsumerWidget {
  const _LoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState.error(
      title: l10n.commonLoadFailed,
      message: '$error',
      retryLabel: l10n.commonRetry,
      onRetry: () {
        ref.invalidate(currentMonthlyCloseProvider);
        ref.invalidate(monthlyCloseEvidenceProvider);
      },
    );
  }
}

class _ClosedMonth extends StatelessWidget {
  const _ClosedMonth({required this.close});

  final MonthlyClose close;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        AppEmptyState(
          icon: FLucideIcons.circleCheckBig,
          title: l10n.monthlyCloseCompleted,
          message: close.overrideReason == null
              ? l10n.monthlyCloseVerifiedBody
              : l10n.monthlyCloseOverriddenBody(close.overrideReason!),
        ),
        for (final step in MonthlyCloseStep.values) ...[
          _CloseStepRow(step: step, state: close.evidence.states[step]!),
          const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

class _CloseStepRow extends ConsumerWidget {
  const _CloseStepRow({required this.step, required this.state});

  final MonthlyCloseStep step;
  final MonthlyCloseStepState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (label, route) = switch (step) {
      MonthlyCloseStep.importReview => (
        l10n.monthlyCloseImport,
        FinanceRoutes.activityIngest,
      ),
      MonthlyCloseStep.inboxClear => (
        l10n.monthlyCloseInbox,
        FinanceRoutes.activityInbox,
      ),
      MonthlyCloseStep.accountReconcile => (
        l10n.monthlyCloseAccounts,
        FinanceRoutes.wealthAccounts,
      ),
      MonthlyCloseStep.runwayReview => (
        l10n.monthlyCloseRunway,
        FinanceRoutes.planRunway,
      ),
      MonthlyCloseStep.actionReview => (
        l10n.monthlyCloseActions,
        ref.watch(lifeActionReviewRouteProvider) ?? FinanceRoutes.home,
      ),
    };
    final accepted =
        state == MonthlyCloseStepState.verified ||
        state == MonthlyCloseStepState.overridden;
    return SoftCard.raised(
      borderless: true,
      onPress: () => context.push(route),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          Icon(
            accepted ? FLucideIcons.circleCheckBig : FLucideIcons.circleAlert,
            color: accepted
                ? SemanticColors.of(context).success
                : SemanticColors.of(context).warning,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(child: Text(label, style: context.labelStyle)),
          AppBadge(
            label: _stateLabel(l10n, state),
            size: AppBadgeSize.compact,
            tone: accepted ? AppBadgeTone.success : AppBadgeTone.warning,
          ),
        ],
      ),
    );
  }
}

class _ReconciliationRow extends ConsumerWidget {
  const _ReconciliationRow({required this.target});

  final ReconciliationTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reconciliation = target.reconciliation;
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(target.accountName, style: context.labelStyle),
              ),
              Text(
                '${target.ledgerBalance} ${target.unit}',
                style: TypographyTokens.numericBodyStrong,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(l10n.monthlyCloseLedgerBalance, style: context.captionStyle),
          if (reconciliation != null) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              l10n.monthlyCloseDifference(
                reconciliation.difference.toString(),
                target.unit,
              ),
              style: context.captionStyle,
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (reconciliation?.status ==
                  AccountReconciliationStatus.mismatch)
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => _override(context, ref, reconciliation!),
                  child: Text(l10n.monthlyCloseAcceptDifference),
                ),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () => _verify(context, ref),
                child: Text(l10n.monthlyCloseEnterStatementBalance),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final raw = await _textPrompt(
      context,
      title: l10n.monthlyCloseStatementBalanceTitle(target.accountName),
      hint: target.ledgerBalance.toString(),
      numeric: true,
    );
    final balance = raw == null ? null : Decimal.tryParse(raw);
    if (balance == null) return;
    final repository = await ref.read(
      accountReconciliationRepositoryProvider.future,
    );
    await repository.verify(
      periodMonth: ref.read(currentClosePeriodProvider),
      accountId: target.accountId,
      unit: target.unit,
      statementBalance: balance,
      now: DateTime.now(),
    );
    ref.invalidate(monthlyCloseEvidenceProvider);
  }

  Future<void> _override(
    BuildContext context,
    WidgetRef ref,
    AccountReconciliation reconciliation,
  ) async {
    final l10n = AppLocalizations.of(context);
    final note = await _textPrompt(
      context,
      title: l10n.monthlyCloseDifferenceReasonTitle,
      hint: l10n.monthlyCloseDifferenceReasonHint,
    );
    if (note == null) return;
    final repository = await ref.read(
      accountReconciliationRepositoryProvider.future,
    );
    await repository.overrideMismatch(
      reconciliation: reconciliation,
      note: note,
      now: DateTime.now(),
    );
    ref.invalidate(monthlyCloseEvidenceProvider);
  }
}

String _stateLabel(AppLocalizations l10n, MonthlyCloseStepState state) =>
    switch (state) {
      MonthlyCloseStepState.blocked => l10n.monthlyCloseStateBlocked,
      MonthlyCloseStepState.ready => l10n.monthlyCloseStateReady,
      MonthlyCloseStepState.verified => l10n.monthlyCloseStateVerified,
      MonthlyCloseStepState.overridden => l10n.monthlyCloseStateOverridden,
    };

Future<String?> _textPrompt(
  BuildContext context, {
  required String title,
  required String hint,
  bool numeric = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
          },
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
