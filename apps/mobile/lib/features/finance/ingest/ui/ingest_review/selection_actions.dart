part of '../ingest_review_page.dart';

class _IngestSelectionActions extends StatelessWidget {
  const _IngestSelectionActions({
    required this.count,
    required this.busy,
    required this.canConfirm,
    required this.canDismiss,
    required this.canFinalize,
    required this.onConfirm,
    required this.onDismiss,
    required this.onFinalize,
  });

  final int count;
  final bool busy;
  final bool canConfirm;
  final bool canDismiss;
  final bool canFinalize;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(l10n.commonSelectedCount(count), style: context.labelStyle),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (canConfirm)
                  AppActionButton(
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onConfirm,
                    child: Text(l10n.ingestConfirm),
                  ),
                if (canDismiss) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onDismiss,
                    child: Text(l10n.ingestSkip),
                  ),
                ],
                if (canFinalize) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.primary,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onFinalize,
                    child: Text(l10n.ingestResolveAction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
