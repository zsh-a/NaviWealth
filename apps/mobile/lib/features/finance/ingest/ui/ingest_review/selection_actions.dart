part of '../ingest_review_page.dart';

class _IngestSelectionActions extends StatelessWidget {
  const _IngestSelectionActions({
    required this.count,
    required this.busy,
    required this.confirmCount,
    required this.dismissCount,
    required this.finalizeCount,
    required this.onCategory,
    required this.onConfirm,
    required this.onDismiss,
    required this.onFinalize,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final int confirmCount;
  final int dismissCount;
  final int finalizeCount;
  final VoidCallback? onCategory;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final VoidCallback onFinalize;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s4,
                children: [
                  Text(
                    l10n.commonSelectedCount(count),
                    style: context.labelStyle,
                  ),
                  Text(
                    l10n.ingestSelectionEligibility(
                      confirmCount,
                      count - confirmCount,
                    ),
                    style: context.bodyCaptionStyle,
                  ),
                ],
              ),
            ),
            AppIconButton(
              key: const ValueKey('ingest-selection-cancel'),
              tooltip: l10n.ingestClearSelection,
              icon: FLucideIcons.x,
              onPress: busy ? null : onClear,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            if (confirmCount > 0)
              AppActionButton(
                mainAxisSize: MainAxisSize.min,
                onPress: busy ? null : onConfirm,
                child: Flexible(
                  child: Text(l10n.ingestConfirmSelected(confirmCount)),
                ),
              ),
            if (dismissCount > 0)
              AppActionButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: busy ? null : onDismiss,
                child: Flexible(child: Text(l10n.ingestSkip)),
              ),
            if (onCategory != null)
              AppActionButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: busy ? null : onCategory,
                child: Flexible(child: Text(l10n.ingestBatchCategory)),
              ),
            if (finalizeCount > 0)
              AppActionButton(
                variant: FButtonVariant.primary,
                mainAxisSize: MainAxisSize.min,
                onPress: busy ? null : onFinalize,
                child: Flexible(child: Text(l10n.ingestResolveAction)),
              ),
          ],
        ),
      ],
    );
  }
}
