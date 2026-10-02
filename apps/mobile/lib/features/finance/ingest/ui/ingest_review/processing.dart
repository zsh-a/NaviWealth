part of '../ingest_review_page.dart';

enum _IngestAction { parsing, confirming, confirmingBatch, undoing }

class _IngestBusyState {
  const _IngestBusyState({
    required this.action,
    required this.title,
    required this.message,
    required this.icon,
    this.completed,
    this.total,
  });

  final _IngestAction action;
  final String title;
  final String message;
  final IconData icon;
  final int? completed;
  final int? total;
}

class _ProcessingState extends StatelessWidget {
  const _ProcessingState({required this.state});

  final _IngestBusyState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.formColumn),
          child: _ProcessingPanel(state: state),
        ),
      ),
    );
  }
}

class _ProcessingNotice extends StatelessWidget {
  const _ProcessingNotice({required this.state});

  final _IngestBusyState state;

  @override
  Widget build(BuildContext context) {
    return _ProcessingPanel(state: state, compact: true);
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel({
    required this.state,
    this.compact = false,
    this.onStop,
    this.stopRequested = false,
  });

  final _IngestBusyState state;
  final bool compact;
  final VoidCallback? onStop;
  final bool stopRequested;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.raised(
      key: ValueKey(state.action),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.total != null && state.total! > 0)
              FDeterminateProgress(
                value: ((state.completed ?? 0) / state.total!).clamp(0, 1),
                semanticsLabel: state.message,
              )
            else
              FProgress(
                style: FProgressStyle(
                  constraints: const BoxConstraints.tightFor(height: 2),
                  trackDecoration: ShapeDecoration(
                    shape: RoundedSuperellipseBorder(
                      borderRadius: context.theme.style.borderRadius.pill,
                    ),
                    color: colors.muted,
                  ),
                  fillDecoration: ShapeDecoration(
                    shape: RoundedSuperellipseBorder(
                      borderRadius: context.theme.style.borderRadius.pill,
                    ),
                    color: colors.primary,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(
                compact ? AppSpacing.s12 : AppSpacing.s20,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 34 : 40,
                    height: compact ? 34 : 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: AppOpacity.light),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      state.icon,
                      size: compact ? AppIconSizes.sm : AppIconSizes.md,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.title, style: context.labelStyle),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          state.message,
                          style: context.bodyCaptionStyle.copyWith(
                            height: 1.35,
                          ),
                        ),
                        if (onStop != null || stopRequested) ...[
                          const SizedBox(height: AppSpacing.s8),
                          AppActionButton(
                            variant: FButtonVariant.outline,
                            onPress: onStop,
                            child: Flexible(
                              child: Text(
                                stopRequested
                                    ? AppLocalizations.of(context)
                                          .ingestStopping
                                    : AppLocalizations.of(context)
                                          .ingestStopBatch,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
