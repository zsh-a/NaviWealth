import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../composition/finance_route_paths.dart';

/// Completion moment for a batch import (doc 11 触发器 "完成大型操作").
///
/// A transient toast under-sells a 20-entry import; this sheet gives the
/// batch one deliberate beat — a success mark that scales in, the recorded
/// count rolling up, and a path onward into the activity feed — then gets
/// out of the way. Single-entry confirms keep the lightweight toast.
Future<void> showIngestSummarySheet(
  BuildContext context, {
  required int recorded,
  required int needsReview,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.ingestRecorded,
    builder: (sheetContext) => _IngestSummaryBody(
      recorded: recorded,
      needsReview: needsReview,
      onViewActivity: () {
        Navigator.of(sheetContext).pop();
        GoRouter.of(context).go(FinanceRoutes.activity);
      },
    ),
  );
}

class _IngestSummaryBody extends StatelessWidget {
  const _IngestSummaryBody({
    required this.recorded,
    required this.needsReview,
    required this.onViewActivity,
  });

  final int recorded;
  final int needsReview;
  final VoidCallback onViewActivity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final success = context.appTheme.status.success;
    return Padding(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success mark scales in once.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: AppMotionPolicy.duration(
              context,
              Motion.slow,
              role: AppMotionRole.status,
            ),
            curve: Motion.emphasizedDecelerate,
            builder: (context, t, child) =>
                Transform.scale(scale: t, child: child),
            child: Center(
              child: Container(
                width: AppIconSizes.heroLg,
                height: AppIconSizes.heroLg,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: success.container,
                ),
                child: Icon(
                  FLucideIcons.check,
                  size: AppIconSizes.xl,
                  color: success.onContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          // Recorded count rolls up to its final value.
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: recorded.toDouble()),
              duration: AppMotionPolicy.duration(
                context,
                Motion.ticker,
                role: AppMotionRole.status,
              ),
              curve: Motion.emphasizedDecelerate,
              builder: (context, value, _) => Text(
                l10n.ingestSummaryTitle(value.round()),
                style: TypographyTokens.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.ingestSummaryBody,
            style: context.bodyCaptionStyle,
            textAlign: TextAlign.center,
          ),
          if (needsReview > 0) ...[
            const SizedBox(height: AppSpacing.s12),
            Center(
              child: AppBadge(
                label: l10n.ingestSummaryFailures(needsReview),
                tone: AppBadgeTone.warning,
                icon: FLucideIcons.circleAlert,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s24),
          FButton(
            onPress: onViewActivity,
            child: Text(l10n.ingestSummaryViewActivity),
          ),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).commonDone),
          ),
        ],
      ),
    );
  }
}
