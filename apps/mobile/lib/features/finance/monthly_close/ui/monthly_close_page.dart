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

  Future<void> _beginSession({
    required String period,
    required MonthlyCloseEvidence evidence,
  }) async {
    if (_beginRequestedFor == period) return;
    setState(() => _beginRequestedFor = period);
    try {
      final repository = await ref.read(monthlyCloseRepositoryProvider.future);
      await repository.begin(
        periodMonth: period,
        evidence: evidence,
        snapshot: evidence.details,
        now: DateTime.now(),
      );
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'start monthly close',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _beginRequestedFor = null);
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
    final history = ref.watch(monthlyCloseHistoryProvider).value ?? const [];
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
            data: (evidence) {
              if (close == null) {
                return _StartMonthlyClose(
                  period: period,
                  evidence: evidence,
                  busy: _beginRequestedFor == period,
                  onStart: () =>
                      _beginSession(period: period, evidence: evidence),
                );
              }
              return ListView(
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
                  _CloseStepsGroup(evidence: evidence),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    l10n.monthlyCloseReconciliationTitle,
                    style: context.rowTitleStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  targetsAsync.when(
                    loading: () => const Center(child: FCircularProgress()),
                    error: (error, stackTrace) => AppEmptyState.error(
                      compact: true,
                      title: l10n.commonLoadFailed,
                      message: userSafeErrorMessage(
                        context,
                        error,
                        stackTrace: stackTrace,
                        operation: 'load reconciliation targets',
                      ),
                      retryLabel: l10n.commonRetry,
                      onRetry: () =>
                          ref.invalidate(reconciliationTargetsProvider),
                    ),
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
                      startedAt: close.startedAt,
                    ),
                    child: Text(
                      evidence.isVerified
                          ? l10n.monthlyCloseComplete
                          : l10n.monthlyCloseWithException,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  _CloseHistory(closes: history),
                ],
              );
            },
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

class _StartMonthlyClose extends StatelessWidget {
  const _StartMonthlyClose({
    required this.period,
    required this.evidence,
    required this.busy,
    required this.onStart,
  });

  final String period;
  final MonthlyCloseEvidence evidence;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        _CloseProgress(evidence: evidence, comparison: null),
        const SizedBox(height: AppSpacing.s16),
        AppEmptyState(
          icon: FLucideIcons.clipboardCheck,
          title: l10n.monthlyClosePeriod(period),
          message: l10n.monthlyCloseStartBody,
          action: AppBusyButton(
            busy: busy,
            onPress: onStart,
            label: l10n.monthlyCloseStart,
          ),
        ),
      ],
    );
  }
}

class _CloseStepsGroup extends StatelessWidget {
  const _CloseStepsGroup({required this.evidence});

  final MonthlyCloseEvidence evidence;

  @override
  Widget build(BuildContext context) {
    const steps = MonthlyCloseStep.values;
    return AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            _CloseStepRow(
              step: steps[index],
              state: evidence.states[steps[index]]!,
            ),
            if (index < steps.length - 1)
              const AppGroupedDivider(indent: AppSpacing.s48),
          ],
        ],
      ),
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
            if (comparison!.carriedSignalKeys.isNotEmpty ||
                comparison!.carriedReconciliationKeys.isNotEmpty)
              Text(
                l10n.monthlyCloseCarriedForward(
                  comparison!.carriedSignalKeys.length,
                  comparison!.carriedReconciliationKeys.length,
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

class _ClosedMonth extends ConsumerWidget {
  const _ClosedMonth({required this.close});

  final MonthlyClose close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const SizedBox(height: AppSpacing.s16),
        _CloseHistory(
          closes: ref.watch(monthlyCloseHistoryProvider).value ?? const [],
        ),
      ],
    );
  }
}

class _CloseHistory extends StatefulWidget {
  const _CloseHistory({required this.closes});

  final List<MonthlyClose> closes;

  @override
  State<_CloseHistory> createState() => _CloseHistoryState();
}

class _CloseHistoryState extends State<_CloseHistory> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.closes.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDisclosureHeader(
          title: l10n.monthlyCloseHistoryTitle,
          subtitle: l10n.monthlyCloseHistoryCount(widget.closes.length),
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
        ),
        AnimatedSizeFade(
          visible: _expanded,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < widget.closes.take(6).length;
                    index++
                  ) ...[
                    _CloseHistoryRow(close: widget.closes[index]),
                    if (index < widget.closes.take(6).length - 1)
                      const AppGroupedDivider(indent: AppSpacing.s12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseHistoryRow extends StatelessWidget {
  const _CloseHistoryRow({required this.close});

  final MonthlyClose close;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(close.periodMonth, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.monthlyCloseHistoryExceptions(
                    _historyExceptionCount(close),
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          Text(
            _historyDuration(l10n, close),
            style: TypographyTokens.numericBodyStrong,
          ),
        ],
      ),
    );
  }
}

int _historyExceptionCount(MonthlyClose close) =>
    _snapshotList(close, 'active_signal_keys').length +
    _snapshotList(close, 'reconciliation_exception_keys').length;

Iterable<Object?> _snapshotList(MonthlyClose close, String key) =>
    close.snapshot[key] as Iterable<Object?>? ?? const <Object?>[];

String _historyDuration(AppLocalizations l10n, MonthlyClose close) {
  final milliseconds = (close.snapshot['close_duration_ms'] as num?)?.toInt();
  return milliseconds == null
      ? '—'
      : l10n.monthlyCloseHistoryDuration(
          Duration(milliseconds: milliseconds).inMinutes,
        );
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
    return SoftCard.flat(
      tinted: false,
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
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
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
  return showAppTextPromptSheet(
    context: context,
    title: title,
    fieldLabel: title,
    hint: hint,
    submitLabel: l10n.commonConfirm,
    cancelLabel: l10n.commonCancel,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    validator: (value) {
      if (value.isEmpty) return l10n.commonRequiredField;
      if (numeric && Decimal.tryParse(value) == null) {
        return l10n.commonInvalidNumber;
      }
      return null;
    },
  );
}
