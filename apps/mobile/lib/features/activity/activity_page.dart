import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/global_action_panel.dart';
import '../../l10n/gen/app_localizations.dart';
import 'data/activity_feed_provider.dart';
import 'data/activity_feed_query.dart';
import 'ui/activity_feed.dart';
import 'ui/activity_feed_filter_sheet.dart';

/// Activity tab — single timeline of every journal entry, with a filter
/// chip row for quickly slicing by entry kind. The legacy three-segment
/// layout (Expenses / Accounts / Feed) is gone; expenses and accounts
/// each have their own first-class detail flow now reachable via deep
/// link or the global action panel ("+").
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  bool _hydratedFromUrl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final query = ActivityFeedQuery.fromUri(uri);
    if (query.hasFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activityFeedQueryProvider.notifier).setQuery(query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<ActivityFeedQuery>(activityFeedQueryProvider, (_, next) {
      if (!mounted) return;
      _replaceActivityUrl(query: next);
    });

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.navActivity),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.filter_list_outlined),
            onPress: () => ActivityFeedFilterSheet.show(context),
          ),
          FHeaderAction(
            icon: const Icon(Icons.add_outlined),
            onPress: () => showGlobalActionPanel(context),
          ),
        ],
      ),
      childPad: false,
      child: const Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActivityKindFilterRow(),
            Expanded(child: ActivityFeed()),
          ],
        ),
      ),
    );
  }

  void _replaceActivityUrl({required ActivityFeedQuery query}) {
    final router = GoRouter.of(context);
    final current = router.routeInformationProvider.value.uri;
    final params = <String, String>{...current.queryParameters};
    params.remove('accounts');
    params.remove('kinds');
    params.remove('from');
    params.remove('to');
    params.remove('tab');
    params.addAll(query.toQueryParameters());
    final next = current.replace(
      path: '/activity',
      queryParameters: params.isEmpty ? null : params,
    );
    if (next.toString() != current.toString()) {
      router.replace<void>(next.toString());
    }
  }
}

/// Quick filter chip row above the timeline. Tapping a chip toggles the
/// corresponding [ActivityKind] in the active feed query — multiple
/// chips can be active simultaneously. The "All" chip clears the kind
/// filter (other filters from the sheet are preserved).
class _ActivityKindFilterRow extends ConsumerWidget {
  const _ActivityKindFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(activityFeedQueryProvider);
    final controller = ref.read(activityFeedQueryProvider.notifier);
    final selected = query.kinds;
    final allActive = selected.isEmpty;

    final chips = <_KindChipSpec>[
      _KindChipSpec(
        label: l10n.activityFilterChipAll,
        active: allActive,
        onTap: () => controller.setQuery(
          query.copyWith(kinds: const <ActivityKind>{}),
        ),
      ),
      for (final kind in const [
        ActivityKind.income,
        ActivityKind.expense,
        ActivityKind.transfer,
        ActivityKind.trade,
      ])
        _KindChipSpec(
          label: _labelForKind(l10n, kind),
          active: selected.contains(kind),
          onTap: () {
            final next = {...selected};
            if (next.contains(kind)) {
              next.remove(kind);
            } else {
              next.add(kind);
            }
            controller.setQuery(query.copyWith(kinds: next));
          },
        ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _FilterChip(spec: chips[i]),
      ),
    );
  }
}

class _KindChipSpec {
  const _KindChipSpec({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.spec});

  final _KindChipSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final fg = spec.active ? colors.primaryForeground : colors.foreground;
    final bg = spec.active ? colors.primary : colors.muted;
    return FTappable(
      onPress: spec.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          spec.label,
          style: context.theme.typography.xs.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _labelForKind(AppLocalizations l10n, ActivityKind kind) {
  return switch (kind) {
    ActivityKind.income => l10n.activityFilterChipIncome,
    ActivityKind.expense => l10n.activityFilterChipExpense,
    ActivityKind.transfer => l10n.activityFilterChipTransfer,
    ActivityKind.trade => l10n.activityFilterChipTrade,
    ActivityKind.payment ||
    ActivityKind.adjustment ||
    ActivityKind.opening ||
    ActivityKind.other => kind.name,
  };
}
