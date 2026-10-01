import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/health_check_in_providers.dart';
import '../data/health_series_providers.dart';
import '../domain/health_check_in.dart';
import 'health_check_in_presentation.dart';
import 'health_check_in_sheet.dart';
import 'health_metric_presentation.dart';

class HealthCheckInToday extends ConsumerWidget {
  const HealthCheckInToday({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final date = ref.watch(healthCalendarDayProvider);
    final async = ref.watch(healthCheckInsProvider(1));
    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SkeletonBox(height: 60),
      error: (error, stack) => kDefaultError(
        context,
        error,
        stack,
        onRetry: () => ref.invalidate(healthCheckInsProvider(1)),
      ),
      data: (entries) {
        final entry = entries.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: l.healthCheckInTitle,
              action: l.healthCheckInRecord,
              onPress: () => showHealthCheckInSheet(
                context: context,
                day: date,
                entry: entry,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (entry == null) ...[
              Text(l.healthCheckInEmpty, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s4),
              Text(l.healthCheckInEmptyHelp, style: context.captionStyle),
            ] else
              HealthCheckInContent(entry: entry),
          ],
        );
      },
    );
  }
}

class HealthCheckInContent extends StatelessWidget {
  const HealthCheckInContent({super.key, required this.entry});
  final HealthCheckIn entry;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final feelings = healthCheckInFeelings(l, entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (feelings.isNotEmpty) Text(feelings, style: context.captionStyle),
        if (entry.tags.isNotEmpty) ...[
          if (feelings.isNotEmpty) const SizedBox(height: AppSpacing.s6),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s6,
            children: [
              for (final tag in entry.tags)
                AppBadge(
                  label: healthEventTagLabel(l, tag),
                  size: AppBadgeSize.compact,
                ),
            ],
          ),
        ],
        if (entry.note case final String note when note.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          Text(note, style: context.captionStyle),
        ],
      ],
    );
  }
}

/// Context for the exact day selected on the metric chart.
class HealthCheckInContext extends StatelessWidget {
  const HealthCheckInContext({
    super.key,
    required this.day,
    required this.entry,
  });
  final DateTime day;
  final HealthCheckIn? entry;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '${l.healthCheckInTitle} · ${healthDateLabel(l, day)}',
          action: entry == null ? l.healthCheckInRecord : l.healthCheckInEdit,
          onPress: () =>
              showHealthCheckInSheet(context: context, day: day, entry: entry),
        ),
        const SizedBox(height: AppSpacing.s4),
        if (entry == null)
          Text(l.healthCheckInContextEmpty, style: context.captionStyle)
        else
          HealthCheckInContent(entry: entry!),
      ],
    );
  }
}

class HealthCheckInHistory extends ConsumerStatefulWidget {
  const HealthCheckInHistory({super.key, required this.days});
  final int days;
  @override
  ConsumerState<HealthCheckInHistory> createState() =>
      _HealthCheckInHistoryState();
}

class _HealthCheckInHistoryState extends ConsumerState<HealthCheckInHistory> {
  bool _expanded = false;
  @override
  void didUpdateWidget(covariant HealthCheckInHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days != widget.days) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(healthCheckInsProvider(widget.days));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l.healthCheckInHistory,
          action: l.healthCheckInRecordDay,
          onPress: () => showHealthCheckInDateSheet(
            context: context,
            today: ref.read(healthClockProvider)(),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        data.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const SkeletonBox(height: 60),
          error: (error, stack) => kDefaultError(
            context,
            error,
            stack,
            onRetry: () => ref.invalidate(healthCheckInsProvider(widget.days)),
          ),
          data: (entries) {
            final visible = _expanded ? entries : entries.take(7).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entries.isEmpty)
                  Text(l.healthCheckInHistoryEmpty, style: context.captionStyle)
                else ...[
                  Text(
                    l.healthCheckInObservedDays(entries.length, widget.days),
                    style: context.captionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  AppGroupedSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (index, entry) in visible.indexed) ...[
                          if (index > 0)
                            const AppGroupedDivider(
                              indent: AppSpacing.s16,
                              endIndent: AppSpacing.s16,
                            ),
                          AppTappable(
                            onPress: () => showHealthCheckInSheet(
                              context: context,
                              day: entry.day,
                              entry: entry,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          healthDateLabel(l, entry.day),
                                          style: context.rowTitleStyle,
                                        ),
                                      ),
                                      const Icon(
                                        FLucideIcons.pencil,
                                        size: AppIconSizes.sm,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  HealthCheckInContent(entry: entry),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (entries.length > 7) ...[
                    const SizedBox(height: AppSpacing.s8),
                    AppRevealControl(
                      expanded: _expanded,
                      collapsedLabel: l.commonRevealMore(entries.length - 7),
                      expandedLabel: l.commonRevealLess,
                      onToggle: () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l.healthCheckInAssociationHelp,
                  style: context.microCaptionStyle,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onPress,
  });
  final String title;
  final String action;
  final VoidCallback onPress;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: Text(title, style: context.labelStyle),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: onPress,
            child: Flexible(child: Text(action)),
          ),
        ),
      ],
    ),
  );
}
