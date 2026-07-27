import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FIRE milestone celebration (doc 11 触发器 "跨越 FIRE 里程碑").
///
/// Crossing a quarter milestone (25 / 50 / 75 / 100 %) earns exactly one
/// celebration, persisted in SharedPreferences so it never replays. The
/// moment itself stays in the app's restrained language: a profit-glow
/// burst behind the milestone figure, a success haptic, auto-dismissed —
/// no confetti physics competing with the dashboard.
final fireMilestoneProvider =
    StateNotifierProvider<FireMilestoneController, int>((ref) {
      return FireMilestoneController(ref.watch(sharedPreferencesProvider));
    });

class FireMilestoneController extends StateNotifier<int> {
  FireMilestoneController(this._prefs)
    : super(_prefs.getInt(_kLastMilestone) ?? 0);

  static const _kLastMilestone = 'naviwealth.fire.last_milestone';

  final SharedPreferences _prefs;

  int get lastCelebrated => state;

  Future<void> markCelebrated(int milestone) async {
    state = milestone;
    await _prefs.setInt(_kLastMilestone, milestone);
  }
}

/// Quarter milestone reached by [progress] (0 when below the first one).
int fireMilestoneFor(double progress) {
  final percent = (progress.clamp(0.0, 1.0) * 100).floor();
  return percent - (percent % 25);
}

/// Celebrate once if [progress] crossed a milestone this install hasn't
/// seen. Call from the FIRE dashboard after data resolves.
Future<void> maybeCelebrateFireMilestone(
  BuildContext context, {
  required double progress,
  required FireMilestoneController controller,
}) async {
  final milestone = fireMilestoneFor(progress);
  if (milestone < 25 || milestone <= controller.lastCelebrated) return;
  await controller.markCelebrated(milestone);
  if (!context.mounted) return;
  AppInteraction.signal(AppInteractionIntent.success);
  await _showCelebrationOverlay(context, milestone);
}

Future<void> _showCelebrationOverlay(BuildContext context, int milestone) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).fireMilestoneReached(milestone),
    barrierColor: context.appTheme.surfaces.scrim,
    transitionDuration: AppMotionPolicy.duration(context, Motion.slow),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.emphasizedDecelerate,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
    pageBuilder: (dialogContext, _, _) =>
        _MilestoneCard(milestone: milestone, dialogContext: dialogContext),
  );
}

class _MilestoneCard extends StatefulWidget {
  const _MilestoneCard({required this.milestone, required this.dialogContext});

  final int milestone;
  final BuildContext dialogContext;

  @override
  State<_MilestoneCard> createState() => _MilestoneCardState();
}

class _MilestoneCardState extends State<_MilestoneCard> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(Motion.shimmerCycle * 2, () {
      if (mounted && Navigator.of(widget.dialogContext).canPop()) {
        Navigator.of(widget.dialogContext).pop();
      }
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final market = context.appTheme.market;
    return Center(
      child: SoftCard.hero(
        padding: AppPageRhythm.heroPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppIconSizes.heroLg,
              height: AppIconSizes.heroLg,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    market.profitGlow,
                    market.profitGlow.withValues(alpha: AppOpacity.transparent),
                  ],
                ),
              ),
              child: Icon(
                FLucideIcons.flame,
                size: AppIconSizes.xl,
                color: context.appTheme.accent.fg,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text('${widget.milestone}%', style: TypographyTokens.displayLarge),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.fireMilestoneReached(widget.milestone),
              style: context.bodyCaptionStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
