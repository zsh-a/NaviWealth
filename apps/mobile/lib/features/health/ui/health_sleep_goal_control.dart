import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_preferences.dart';

class HealthSleepGoalControl extends ConsumerStatefulWidget {
  const HealthSleepGoalControl({super.key});
  @override
  ConsumerState<HealthSleepGoalControl> createState() =>
      _HealthSleepGoalControlState();
}

class _HealthSleepGoalControlState
    extends ConsumerState<HealthSleepGoalControl> {
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.healthSleepGoalTitle, style: context.labelStyle),
        const SizedBox(height: AppSpacing.s4),
        Text(l.healthSleepGoalHelp, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s8),
        ref
            .watch(healthPreferencesProvider)
            .when(
              loading: () => const SkeletonBox(height: 44),
              error: (error, stack) => kDefaultError(
                context,
                error,
                stack,
                onRetry: () => ref.invalidate(healthPreferencesProvider),
              ),
              data: (preferences) => AppAdaptiveChoice<double?>(
                title: l.healthSleepGoalTitle,
                options: [null, for (var i = 8; i <= 24; i++) i / 2],
                value: preferences.sleepGoalHours,
                wideInlineBreakpoint: double.infinity,
                labelOf: (hours) => hours == null
                    ? l.healthSleepGoalAutomatic
                    : l.healthSleepGoalHours(
                        context.formatters(ref).number(hours, decimalDigits: 1),
                      ),
                onChanged: _saving ? null : _save,
              ),
            ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppStatusBanner(message: _error!, kind: AppStatusKind.error),
        ],
      ],
    );
  }

  Future<void> _save(double? hours) async {
    if (_saving) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final store = await container.read(healthPreferencesStoreProvider.future);
      if (store.owner != await container.read(currentUserIdProvider)()) {
        throw StateError('The active user changed.');
      }
      await store.setSleepGoal(hours);
      container.invalidate(healthPreferencesProvider);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = userSafeErrorMessage(
            context,
            error,
            operation: 'save sleep goal',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
