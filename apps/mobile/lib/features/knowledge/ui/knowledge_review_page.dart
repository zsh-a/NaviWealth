/// KnowledgeOS Review tab (`docs/knowledgeos-domain.md` §5).
///
/// 3 cards: due Routines (next_due_at within 7d), due Decisions
/// (review_date passed) and stale Assumptions (active && > 90d
/// unverified). Forui chrome with widget-layer pull-to-refresh.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/assumption_agent.dart';
import '../agents/routine_due_agent.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';

const int _kDecisionReviewRescheduleDays = 90;
const String _kReviewRoutineOrderPrefsKey = 'knowledge.review.routine_order.v1';
const String _kReviewDecisionOrderPrefsKey =
    'knowledge.review.decision_order.v1';
const String _kReviewAssumptionOrderPrefsKey =
    'knowledge.review.assumption_order.v1';

final _reviewActionsRefreshProvider = StateProvider<int>((ref) => 0);

@visibleForTesting
bool shouldShowRoutineInReview(
  KnowledgeRoutine routine,
  DateTime now, {
  Duration lookahead = kRoutineDueLookahead,
}) {
  if (routine.status != RoutineStatus.active) return false;
  final doneAt = routine.lastDoneAt;
  if (doneAt != null && _isSameLocalDay(doneAt, now)) return false;
  return !routine.nextDueAt.toUtc().isAfter(now.add(lookahead).toUtc());
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

List<T> _orderedReviewItems<T>({
  required List<T> items,
  required List<String> order,
  required String Function(T item) idOf,
}) {
  final indexById = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  final out = List<T>.of(items);
  out.sort((a, b) {
    final ai = indexById[idOf(a)];
    final bi = indexById[idOf(b)];
    if (ai == null && bi == null) return 0;
    if (ai == null) return 1;
    if (bi == null) return -1;
    return ai.compareTo(bi);
  });
  return out;
}

Future<void> _persistReviewOrder({
  required WidgetRef ref,
  required String prefsKey,
  required List<String> visibleIds,
}) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final stored = prefs.getStringList(prefsKey) ?? const <String>[];
  final visible = visibleIds.toSet();
  await prefs.setStringList(prefsKey, <String>[
    ...visibleIds,
    for (final id in stored)
      if (!visible.contains(id)) id,
  ]);
  ref.read(_reviewActionsRefreshProvider.notifier).state++;
}

class KnowledgeReviewPage extends ConsumerStatefulWidget {
  const KnowledgeReviewPage({super.key});

  @override
  ConsumerState<KnowledgeReviewPage> createState() =>
      _KnowledgeReviewPageState();
}

class _KnowledgeReviewPageState extends ConsumerState<KnowledgeReviewPage>
    with KnowledgeFabScrollHideMixin {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeReviewTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: onScrollUpdate,
              child: KnowledgePullToRefresh(
                onRefresh: () => _refreshReview(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: shellTabContentPadding(
                    context,
                    bottom: AppSpacing.s64 + AppSpacing.s16,
                  ),
                  children: const <Widget>[
                    KnowledgeAiSuggestionsCard(),
                    SizedBox(height: AppSpacing.s16),
                    _DueRoutinesCard(),
                    SizedBox(height: AppSpacing.s16),
                    _DueReviewsCard(),
                    SizedBox(height: AppSpacing.s16),
                    _StaleAssumptionsCard(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: shellTabFloatingActionBottom(context),
            child: KnowledgeFloatingActionMotion(
              hidden: fabHidden,
              child: const _ReviewCreateFab(),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _refreshReview(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  ref.invalidate(inboxTriageRepositoryProvider);
  ref.read(aiSuggestionsRefreshProvider.notifier).state++;
  ref.read(_reviewActionsRefreshProvider.notifier).state++;
  await Future.wait([
    ref.read(knowledgeRepositoryProvider.future),
    ref.read(inboxTriageRepositoryProvider.future),
  ]);
}

/// Icon-only FAB that opens the review batch-actions sheet.
class _ReviewCreateFab extends ConsumerWidget {
  const _ReviewCreateFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KnowledgeFloatingActionSurface(
      child: FButton(
        variant: FButtonVariant.ghost,
        prefix: const Icon(
          FLucideIcons.listChecks,
          size: AppIconSizes.sm,
          color: ColorPalette.neutral0,
        ),
        onPress: () => _openActionsSheet(context, ref),
        child: const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _openActionsSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      title: l10n.knowledgeReviewTitle,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          AppActionSheetTile(
            icon: FLucideIcons.checkCheck,
            title: l10n.knowledgeReviewMarkAllDone,
            subtitle: l10n.knowledgeReviewRoutinesTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
              final routines = await _loadReviewRoutines(ref);
              if (!context.mounted) return;
              if (routines.isEmpty) {
                AppMessenger.show(
                  context,
                  ToastKind.info,
                  l10n.knowledgeReviewRoutinesEmpty,
                );
                return;
              }
              await _markRoutinesDone(
                context: context,
                ref: ref,
                routines: routines,
              );
            },
          ),
          AppActionSheetTile(
            icon: FLucideIcons.calendarCheck,
            title: l10n.knowledgeReviewMarkAllDecisionsReviewed,
            subtitle: l10n.knowledgeReviewDecisionsTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
              final decisions = await _loadReviewDecisions(ref);
              if (!context.mounted) return;
              if (decisions.isEmpty) {
                AppMessenger.show(
                  context,
                  ToastKind.info,
                  l10n.knowledgeReviewDecisionsEmpty,
                );
                return;
              }
              await _markDecisionsReviewed(
                context: context,
                ref: ref,
                decisions: decisions,
              );
            },
          ),
          AppActionSheetTile(
            icon: FLucideIcons.badgeCheck,
            title: l10n.knowledgeReviewVerifyAllAssumptions,
            subtitle: l10n.knowledgeReviewAssumptionsTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
              final assumptions = await _loadReviewAssumptions(ref);
              if (!context.mounted) return;
              if (assumptions.isEmpty) {
                AppMessenger.show(
                  context,
                  ToastKind.info,
                  l10n.knowledgeReviewAssumptionsEmpty(kAssumptionStaleDays),
                );
                return;
              }
              await _verifyAssumptions(
                context: context,
                ref: ref,
                assumptions: assumptions,
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<String> _reviewOwner(WidgetRef ref) => ref.read(currentUserIdProvider)();

Future<List<KnowledgeRoutine>> _loadReviewRoutines(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final now = DateTime.now();
  return repo.listDueRoutines(
    ownerUserId: owner,
    asOf: now.add(kRoutineDueLookahead).toUtc(),
    excludeDoneSince: DateTime(now.year, now.month, now.day),
    limit: 1000,
  );
}

Future<List<KnowledgeDecision>> _loadReviewDecisions(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  return repo.listDueReviews(
    ownerUserId: owner,
    asOf: DateTime.now().toUtc(),
    limit: 1000,
  );
}

Future<List<KnowledgeAssumption>> _loadReviewAssumptions(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final now = DateTime.now().toUtc();
  final all = await repo.listOpenAssumptions(ownerUserId: owner);
  return all
      .where((a) => a.daysSinceVerify(now) >= kAssumptionStaleDays)
      .toList(growable: false);
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}

/// Shared selection toolbar + reorderable list for Review cards.
/// Encapsulates the `_selectedIds` set, `_ReviewSelectionToolbar`,
/// and `_ReviewReorderableList` pattern that all three cards repeat.
class _ReviewSelectableList<T> extends StatefulWidget {
  const _ReviewSelectableList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.actionLabel,
    required this.icon,
    required this.onBulkAction,
    required this.orderPrefsKey,
    required this.onOrderChanged,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(T item) itemBuilder;
  final String actionLabel;
  final IconData icon;
  final Future<void> Function(List<T> selected) onBulkAction;
  final String orderPrefsKey;
  final ValueChanged<List<String>> onOrderChanged;

  @override
  State<_ReviewSelectableList<T>> createState() =>
      _ReviewSelectableListState<T>();
}

class _ReviewSelectableListState<T> extends State<_ReviewSelectableList<T>> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final visibleIds = {for (final item in widget.items) widget.idOf(item)};
    _selectedIds.removeWhere((id) => !visibleIds.contains(id));
    final selected = widget.items
        .where((item) => _selectedIds.contains(widget.idOf(item)))
        .toList(growable: false);
    return Column(
      children: [
        _ReviewSelectionToolbar(
          selectedCount: selected.length,
          totalCount: widget.items.length,
          actionLabel: widget.actionLabel,
          icon: widget.icon,
          onSelectAll: () => setState(() {
            _selectedIds
              ..clear()
              ..addAll(visibleIds);
          }),
          onClear: () => setState(_selectedIds.clear),
          onRun: selected.isEmpty
              ? null
              : () async {
                  await widget.onBulkAction(selected);
                  if (mounted) setState(_selectedIds.clear);
                },
        ),
        const SizedBox(height: AppSpacing.s8),
        _ReviewReorderableList<T>(
          items: widget.items,
          idOf: widget.idOf,
          itemBuilder: (item) => _SelectableReviewRow(
            selected: _selectedIds.contains(widget.idOf(item)),
            onChanged: () => setState(
              () => _toggleReviewSelection(_selectedIds, widget.idOf(item)),
            ),
            child: widget.itemBuilder(item),
          ),
          onOrderChanged: widget.onOrderChanged,
        ),
      ],
    );
  }
}

class _DueRoutinesCard extends ConsumerWidget {
  const _DueRoutinesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return KnowledgeSection.group(
            title: l10n.knowledgeReviewRoutinesTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => KnowledgeSection.group(
            title: l10n.knowledgeReviewRoutinesTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          ),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewRoutinesTitle,
            children: [
              KnowledgeErrorState(
                title: l10n.knowledgeReviewLoadFailed('$e'),
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (repo) {
            return StreamBuilder<List<KnowledgeRoutine>>(
              stream: repo.watchRoutines(ownerUserId: owner),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewRoutinesTitle,
                    children: [
                      KnowledgeErrorState(
                        title: l10n.knowledgeReviewLoadFailed('${snap.error}'),
                        density: KnowledgeStateDensity.section,
                      ),
                    ],
                  );
                }
                final now = DateTime.now();
                final due = (snap.data ?? const <KnowledgeRoutine>[])
                    .where((r) => shouldShowRoutineInReview(r, now))
                    .toList(growable: false);
                final ordered = _orderedReviewItems<KnowledgeRoutine>(
                  items: due,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(_kReviewRoutineOrderPrefsKey) ??
                      const <String>[],
                  idOf: (r) => r.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewRoutinesTitle,
                  trailing: due.isEmpty
                      ? null
                      : _ReviewBulkActionButton(
                          label: l10n.knowledgeReviewMarkAllDone,
                          icon: FLucideIcons.checkCheck,
                          onPress: () => _markRoutinesDone(
                            context: context,
                            ref: ref,
                            routines: due,
                          ),
                        ),
                  children: [
                    if (due.isEmpty)
                      KnowledgeEmptyState(
                        icon: FLucideIcons.repeat,
                        title: l10n.knowledgeReviewRoutinesEmpty,
                        density: KnowledgeStateDensity.section,
                      )
                    else
                      _ReviewSelectableList<KnowledgeRoutine>(
                        items: visible,
                        idOf: (r) => r.id,
                        itemBuilder: (r) => _DueRoutineRow(routine: r),
                        actionLabel: l10n.knowledgeReviewMarkSelectedDone,
                        icon: FLucideIcons.checkCheck,
                        onBulkAction: (selected) => _markRoutinesDone(
                          context: context,
                          ref: ref,
                          routines: selected,
                        ),
                        orderPrefsKey: _kReviewRoutineOrderPrefsKey,
                        onOrderChanged: (ids) => _persistReviewOrder(
                          ref: ref,
                          prefsKey: _kReviewRoutineOrderPrefsKey,
                          visibleIds: ids,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ReviewBulkActionButton extends StatefulWidget {
  const _ReviewBulkActionButton({
    required this.label,
    required this.icon,
    required this.onPress,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPress;

  @override
  State<_ReviewBulkActionButton> createState() =>
      _ReviewBulkActionButtonState();
}

class _ReviewBulkActionButtonState extends State<_ReviewBulkActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPress();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBusyButton(
      label: widget.label,
      onPress: _run,
      busy: _busy,
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: Icon(widget.icon, size: AppIconSizes.xs),
      busyPrefix: const FCircularProgress(
        size: FCircularProgressSizeVariant.xs,
      ),
      busyLabel: AppLocalizations.of(context).commonSaving,
    );
  }
}

class _ReviewSelectionToolbar extends StatefulWidget {
  const _ReviewSelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.actionLabel,
    required this.icon,
    required this.onSelectAll,
    required this.onClear,
    required this.onRun,
  });

  final int selectedCount;
  final int totalCount;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final Future<void> Function()? onRun;

  @override
  State<_ReviewSelectionToolbar> createState() =>
      _ReviewSelectionToolbarState();
}

class _ReviewSelectionToolbarState extends State<_ReviewSelectionToolbar> {
  bool _busy = false;

  Future<void> _run() async {
    final run = widget.onRun;
    if (_busy || run == null) return;
    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasSelection = widget.selectedCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        children: [
          Text(
            l10n.knowledgeReviewSelectedCount(widget.selectedCount),
            style: context.captionStyle,
          ),
          const Spacer(),
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            onPress: widget.totalCount == 0 ? null : widget.onSelectAll,
            child: Text(l10n.knowledgeReviewSelectAll),
          ),
          const SizedBox(width: AppSpacing.s4),
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            onPress: hasSelection ? widget.onClear : null,
            child: Text(l10n.knowledgeReviewClearSelection),
          ),
          if (hasSelection) ...[
            const SizedBox(width: AppSpacing.s4),
            AppBusyButton(
              label: widget.actionLabel,
              onPress: _run,
              busy: _busy,
              variant: FButtonVariant.primary,
              size: FButtonSizeVariant.sm,
              prefix: Icon(widget.icon, size: AppIconSizes.xs),
              busyPrefix: const FCircularProgress(
                size: FCircularProgressSizeVariant.xs,
              ),
              busyLabel: AppLocalizations.of(context).commonSaving,
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectableReviewRow extends StatelessWidget {
  const _SelectableReviewRow({
    required this.selected,
    required this.onChanged,
    required this.child,
  });

  final bool selected;
  final VoidCallback onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s8),
          child: FCheckbox(value: selected, onChange: (_) => onChanged()),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Compact icon-only action button for review rows. Shows a spinner
/// while busy, the action icon otherwise. Much smaller footprint than
/// the full text button it replaces.
class _ReviewIconButton extends StatelessWidget {
  const _ReviewIconButton({
    required this.icon,
    required this.busy,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final bool busy;
  final String tooltip;
  final Future<bool> Function() onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppIconButton(
      icon: icon,
      tooltip: tooltip,
      onPress: () => onPress(),
      busy: busy,
      size: 32,
      iconSize: AppIconSizes.xs,
      iconColor: colors.primary,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colors.primary.withValues(alpha: AppOpacity.light),
        ),
      ),
    );
  }
}

class _SwipeReviewAction extends StatelessWidget {
  const _SwipeReviewAction({
    required this.dismissKey,
    required this.label,
    required this.icon,
    required this.onComplete,
    required this.child,
  });

  final Key dismissKey;
  final String label;
  final IconData icon;
  final Future<bool> Function() onComplete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onComplete(),
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: context.theme.typography.sm.copyWith(
                color: colors.primaryForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(icon, size: AppIconSizes.sm, color: colors.primaryForeground),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _ReviewReorderableList<T> extends StatefulWidget {
  const _ReviewReorderableList({
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onOrderChanged,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(T item) itemBuilder;
  final ValueChanged<List<String>> onOrderChanged;

  @override
  State<_ReviewReorderableList<T>> createState() =>
      _ReviewReorderableListState<T>();
}

class _ReviewReorderableListState<T> extends State<_ReviewReorderableList<T>> {
  late List<T> _items = List<T>.of(widget.items);

  @override
  void didUpdateWidget(covariant _ReviewReorderableList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = _items.map(widget.idOf).join('\u0001');
    final nextIds = widget.items.map(widget.idOf).join('\u0001');
    if (oldIds != nextIds) {
      _items = List<T>.of(widget.items);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ReorderableList(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final moved = _items.removeAt(oldIndex);
          _items.insert(newIndex, moved);
        });
        widget.onOrderChanged(_items.map(widget.idOf).toList(growable: false));
      },
      itemBuilder: (context, index) {
        final item = _items[index];
        return Row(
          key: ValueKey<String>('review-order-${widget.idOf(item)}'),
          children: [
            Expanded(child: widget.itemBuilder(item)),
            const SizedBox(width: AppSpacing.s4),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s6),
                child: Icon(
                  FLucideIcons.gripVertical,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _markRoutinesDone({
  required BuildContext context,
  required WidgetRef ref,
  required List<KnowledgeRoutine> routines,
}) async {
  if (routines.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    for (final r in routines) {
      final stamp = await stamper.stamp();
      final next = stamp.now.add(Duration(days: r.intervalDays));
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: r.id,
          statement: r.statement,
          intervalDays: r.intervalDays,
          nextDueAt: next,
          lastDoneAt: stamp.now,
          scope: r.scope,
          status: r.status,
          createdAt: r.createdAt,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }
    ref.read(_reviewActionsRefreshProvider.notifier).state++;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeReviewRoutinesBulkDone(routines.length),
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.knowledgeReviewRoutineDoneFailed('$e'),
      );
    }
  }
}

Future<void> _verifyAssumptions({
  required BuildContext context,
  required WidgetRef ref,
  required List<KnowledgeAssumption> assumptions,
}) async {
  if (assumptions.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    for (final a in assumptions) {
      final stamp = await stamper.stamp();
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: a.id,
          statement: a.statement,
          confidence: a.confidence,
          scope: a.scope,
          evidenceIds: a.evidenceIds,
          status: a.status,
          declaredAt: a.declaredAt,
          lastVerifiedAt: stamp.now,
          mergedIntoId: a.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
    }
    ref.read(_reviewActionsRefreshProvider.notifier).state++;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeReviewAssumptionsBulkVerified(assumptions.length),
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.knowledgeReviewAssumptionVerifyFailed('$e'),
      );
    }
  }
}

class _DueRoutineRow extends ConsumerStatefulWidget {
  const _DueRoutineRow({required this.routine});
  final KnowledgeRoutine routine;
  @override
  ConsumerState<_DueRoutineRow> createState() => _DueRoutineRowState();
}

class _DueRoutineRowState extends ConsumerState<_DueRoutineRow> {
  bool _busy = false;

  Future<bool> _markDone() async {
    if (_busy) return false;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final r = widget.routine;
      final next = stamp.now.add(Duration(days: r.intervalDays));
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: r.id,
          statement: r.statement,
          intervalDays: r.intervalDays,
          nextDueAt: next,
          lastDoneAt: stamp.now,
          scope: r.scope,
          status: r.status,
          createdAt: r.createdAt,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) {
        ref.read(_reviewActionsRefreshProvider.notifier).state++;
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewRoutineDone(
            knowledgeDate(context, next, long: true),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewRoutineDoneFailed('$e'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final now = DateTime.now();
    final days = widget.routine.daysUntilDue(now);
    final dueLabel = days < 0
        ? l10n.knowledgeRoutineOverdueDays(-days)
        : days == 0
        ? l10n.knowledgeRoutineDueToday
        : l10n.knowledgeRoutineDueInDays(days);
    final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('routine-review-${widget.routine.id}'),
      label: l10n.knowledgeReviewMarkDone,
      icon: FLucideIcons.check,
      onComplete: _markDone,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          children: [
            Icon(
              FLucideIcons.repeat,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.routine.statement,
                    style: typography.sm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.knowledgeReviewRoutineMeta(
                      dueLabel,
                      widget.routine.intervalDays,
                    ),
                    style: typography.xs.copyWith(color: dueColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            _ReviewIconButton(
              icon: FLucideIcons.check,
              busy: _busy,
              tooltip: l10n.knowledgeReviewMarkDone,
              onPress: _markDone,
            ),
          ],
        ),
      ),
    );
  }
}

class _DueReviewsCard extends ConsumerWidget {
  const _DueReviewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return KnowledgeSection.group(
            title: l10n.knowledgeReviewDecisionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => KnowledgeSection.group(
            title: l10n.knowledgeReviewDecisionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          ),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewDecisionsTitle,
            children: [
              KnowledgeErrorState(
                title: l10n.knowledgeReviewLoadFailed('$e'),
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (repo) {
            final tick = ref.watch(_reviewActionsRefreshProvider);
            return FutureBuilder<List<KnowledgeDecision>>(
              key: ValueKey<int>(tick),
              future: repo.listDueReviews(
                ownerUserId: owner,
                asOf: DateTime.now().toUtc(),
              ),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewDecisionsTitle,
                    children: [
                      KnowledgeErrorState(
                        title: l10n.knowledgeReviewLoadFailed('${snap.error}'),
                        density: KnowledgeStateDensity.section,
                      ),
                    ],
                  );
                }
                final list = snap.data ?? const [];
                final ordered = _orderedReviewItems<KnowledgeDecision>(
                  items: list,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(_kReviewDecisionOrderPrefsKey) ??
                      const <String>[],
                  idOf: (d) => d.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewDecisionsTitle,
                  trailing: list.isEmpty
                      ? null
                      : _ReviewBulkActionButton(
                          label: l10n.knowledgeReviewMarkAllDecisionsReviewed,
                          icon: FLucideIcons.calendarCheck,
                          onPress: () => _markDecisionsReviewed(
                            context: context,
                            ref: ref,
                            decisions: list,
                          ),
                        ),
                  children: [
                    if (list.isEmpty)
                      KnowledgeEmptyState(
                        icon: FLucideIcons.calendar,
                        title: l10n.knowledgeReviewDecisionsEmpty,
                        density: KnowledgeStateDensity.section,
                      )
                    else
                      _ReviewSelectableList<KnowledgeDecision>(
                        items: visible,
                        idOf: (d) => d.id,
                        itemBuilder: (d) => _DueDecisionRow(decision: d),
                        actionLabel:
                            l10n.knowledgeReviewMarkSelectedDecisionsReviewed,
                        icon: FLucideIcons.calendarCheck,
                        onBulkAction: (selected) => _markDecisionsReviewed(
                          context: context,
                          ref: ref,
                          decisions: selected,
                        ),
                        orderPrefsKey: _kReviewDecisionOrderPrefsKey,
                        onOrderChanged: (ids) => _persistReviewOrder(
                          ref: ref,
                          prefsKey: _kReviewDecisionOrderPrefsKey,
                          visibleIds: ids,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DueDecisionRow extends ConsumerStatefulWidget {
  const _DueDecisionRow({required this.decision});

  final KnowledgeDecision decision;

  @override
  ConsumerState<_DueDecisionRow> createState() => _DueDecisionRowState();
}

class _DueDecisionRowState extends ConsumerState<_DueDecisionRow> {
  bool _busy = false;

  Future<bool> _markReviewed() async {
    if (_busy) return false;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final next = await _upsertDecisionReviewDate(
        ref: ref,
        decision: widget.decision,
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewDecisionNextReview(
            knowledgeDate(context, next, long: true),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewDecisionReviewFailed('$e'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final overdueDays =
        widget.decision.daysOverdue(DateTime.now().toUtc()) ?? 0;
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('decision-review-${widget.decision.id}'),
      label: l10n.knowledgeReviewDecisionReviewed,
      icon: FLucideIcons.calendarCheck,
      onComplete: _markReviewed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          children: [
            Icon(
              FLucideIcons.calendar,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Text(
                widget.decision.question,
                style: typography.sm,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            Text(
              l10n.knowledgeReviewDecisionOverdueDays(overdueDays),
              style: context.captionStyle,
            ),
            const SizedBox(width: AppSpacing.s4),
            _ReviewIconButton(
              icon: FLucideIcons.calendarCheck,
              busy: _busy,
              tooltip: l10n.knowledgeReviewDecisionReviewed,
              onPress: _markReviewed,
            ),
          ],
        ),
      ),
    );
  }
}

Future<DateTime> _upsertDecisionReviewDate({
  required WidgetRef ref,
  required KnowledgeDecision decision,
}) async {
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final stamper = await ref.read(mutationStamperProvider.future);
  final stamp = await stamper.stamp();
  final nextReview = stamp.now
      .add(const Duration(days: _kDecisionReviewRescheduleDays))
      .toUtc();
  await repo.upsertDecision(
    KnowledgeDecision(
      id: decision.id,
      question: decision.question,
      options: decision.options,
      selectedLabel: decision.selectedLabel,
      rationaleMd: decision.rationaleMd,
      principleIds: decision.principleIds,
      assumptionIds: decision.assumptionIds,
      expectedOutcome: decision.expectedOutcome,
      reviewDate: nextReview,
      actualOutcomeMd: decision.actualOutcomeMd,
      status: decision.status,
      supersededByDecisionId: decision.supersededByDecisionId,
      contextSnapshot: decision.contextSnapshot,
      decidedAt: decision.decidedAt,
      mergedIntoId: decision.mergedIntoId,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    ),
  );
  return nextReview;
}

Future<void> _markDecisionsReviewed({
  required BuildContext context,
  required WidgetRef ref,
  required List<KnowledgeDecision> decisions,
}) async {
  if (decisions.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  try {
    for (final d in decisions) {
      await _upsertDecisionReviewDate(ref: ref, decision: d);
    }
    ref.read(_reviewActionsRefreshProvider.notifier).state++;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeReviewDecisionsBulkReviewed(decisions.length),
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.knowledgeReviewDecisionReviewFailed('$e'),
      );
    }
  }
}

class _StaleAssumptionsCard extends ConsumerWidget {
  const _StaleAssumptionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          ),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: [
              KnowledgeErrorState(
                title: l10n.knowledgeReviewLoadFailed('$e'),
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (repo) {
            final tick = ref.watch(_reviewActionsRefreshProvider);
            return FutureBuilder(
              key: ValueKey<int>(tick),
              future: repo.listOpenAssumptions(ownerUserId: owner),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewAssumptionsTitle,
                    children: [
                      KnowledgeErrorState(
                        title: l10n.knowledgeReviewLoadFailed('${snap.error}'),
                        density: KnowledgeStateDensity.section,
                      ),
                    ],
                  );
                }
                final all = snap.data ?? const [];
                final now = DateTime.now().toUtc();
                final stale = all
                    .where(
                      (a) => a.daysSinceVerify(now) >= kAssumptionStaleDays,
                    )
                    .toList();
                final ordered = _orderedReviewItems<KnowledgeAssumption>(
                  items: stale,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(_kReviewAssumptionOrderPrefsKey) ??
                      const <String>[],
                  idOf: (a) => a.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewAssumptionsTitle,
                  trailing: stale.isEmpty
                      ? null
                      : _ReviewBulkActionButton(
                          label: l10n.knowledgeReviewVerifyAllAssumptions,
                          icon: FLucideIcons.badgeCheck,
                          onPress: () => _verifyAssumptions(
                            context: context,
                            ref: ref,
                            assumptions: stale,
                          ),
                        ),
                  children: [
                    if (stale.isEmpty)
                      KnowledgeEmptyState(
                        icon: FLucideIcons.badgeCheck,
                        title: l10n.knowledgeReviewAssumptionsEmpty(
                          kAssumptionStaleDays,
                        ),
                        density: KnowledgeStateDensity.section,
                      )
                    else
                      _ReviewSelectableList<KnowledgeAssumption>(
                        items: visible,
                        idOf: (a) => a.id,
                        itemBuilder: (a) =>
                            _StaleAssumptionRow(assumption: a, now: now),
                        actionLabel:
                            l10n.knowledgeReviewVerifySelectedAssumptions,
                        icon: FLucideIcons.badgeCheck,
                        onBulkAction: (selected) => _verifyAssumptions(
                          context: context,
                          ref: ref,
                          assumptions: selected,
                        ),
                        orderPrefsKey: _kReviewAssumptionOrderPrefsKey,
                        onOrderChanged: (ids) => _persistReviewOrder(
                          ref: ref,
                          prefsKey: _kReviewAssumptionOrderPrefsKey,
                          visibleIds: ids,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StaleAssumptionRow extends ConsumerStatefulWidget {
  const _StaleAssumptionRow({required this.assumption, required this.now});

  final KnowledgeAssumption assumption;
  final DateTime now;

  @override
  ConsumerState<_StaleAssumptionRow> createState() =>
      _StaleAssumptionRowState();
}

class _StaleAssumptionRowState extends ConsumerState<_StaleAssumptionRow> {
  bool _busy = false;

  Future<bool> _verify() async {
    if (_busy) return false;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final a = widget.assumption;
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: a.id,
          statement: a.statement,
          confidence: a.confidence,
          scope: a.scope,
          evidenceIds: a.evidenceIds,
          status: a.status,
          declaredAt: a.declaredAt,
          lastVerifiedAt: stamp.now,
          mergedIntoId: a.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) {
        ref.read(_reviewActionsRefreshProvider.notifier).state++;
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewAssumptionVerified,
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewAssumptionVerifyFailed('$e'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('assumption-review-${widget.assumption.id}'),
      label: l10n.knowledgeReviewVerifyAssumption,
      icon: FLucideIcons.badgeCheck,
      onComplete: _verify,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.knowledgeReviewAssumptionStaleSummary(
                  widget.assumption.statement,
                  widget.assumption.daysSinceVerify(widget.now),
                  widget.assumption.confidence.toStringAsFixed(2),
                ),
                style: typography.sm,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            _ReviewIconButton(
              icon: FLucideIcons.badgeCheck,
              busy: _busy,
              tooltip: l10n.knowledgeReviewVerifyAssumption,
              onPress: _verify,
            ),
          ],
        ),
      ),
    );
  }
}
