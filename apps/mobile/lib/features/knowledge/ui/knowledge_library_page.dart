/// KnowledgeOS Library tab (`docs/knowledgeos-domain.md` §5).
///
/// 4 segments: Decisions / Notes / Concepts / Experiments. Decisions
/// surface a status badge per the 7-state lifecycle in §9. Forui-only
/// — no Material widgets so the page renders correctly inside any
/// scope without a Material ancestor.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../app/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

enum _LibrarySegment { decisions, notes, concepts, experiments, routines }

String _segmentLabel(AppLocalizations l10n, _LibrarySegment segment) {
  return switch (segment) {
    _LibrarySegment.decisions => l10n.knowledgeSegmentDecisions,
    _LibrarySegment.notes => l10n.knowledgeSegmentNotes,
    _LibrarySegment.concepts => l10n.knowledgeSegmentConcepts,
    _LibrarySegment.experiments => l10n.knowledgeSegmentExperiments,
    _LibrarySegment.routines => l10n.knowledgeSegmentRoutines,
  };
}

class KnowledgeLibraryPage extends ConsumerStatefulWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  ConsumerState<KnowledgeLibraryPage> createState() =>
      _KnowledgeLibraryPageState();
}

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage> {
  _LibrarySegment _segment = _LibrarySegment.decisions;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeLibraryTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s8,
                AppSpacing.s16,
                AppSpacing.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedRow<_LibrarySegment>(
                    options: _LibrarySegment.values,
                    value: _segment,
                    labelOf: (s) => _segmentLabel(l10n, s),
                    onChanged: (s) => setState(() => _segment = s),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Row(
                    children: [
                      Expanded(
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: _searchCtrl,
                          ),
                          hint: l10n.knowledgeLibrarySearchHint,
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.s8),
                        FButton.icon(
                          variant: FButtonVariant.ghost,
                          onPress: _searchCtrl.clear,
                          child: const Icon(FLucideIcons.x),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Expanded(
                    child: _LibraryList(
                      segment: _segment,
                      query: _searchCtrl.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: _NewObjectButton(segment: _segment),
          ),
        ],
      ),
    );
  }
}

/// FAB-style button that opens the right writer for the current
/// segment. The Decision tab additionally surfaces Principle /
/// Assumption shortcuts in an action sheet so the Library tab can
/// reach every write path without 4 separate FABs.
class _NewObjectButton extends ConsumerWidget {
  const _NewObjectButton({required this.segment});
  final _LibrarySegment segment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = switch (segment) {
      _LibrarySegment.decisions => l10n.knowledgeNewDecision,
      _LibrarySegment.notes => l10n.knowledgeNewNote,
      _LibrarySegment.concepts => l10n.knowledgeNewConcept,
      _LibrarySegment.experiments => l10n.knowledgeNewExperiment,
      _LibrarySegment.routines => l10n.knowledgeNewRoutine,
    };
    return FButton(
      prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
      onPress: () => _onPress(context, ref),
      child: Text(label),
    );
  }

  Future<void> _onPress(BuildContext context, WidgetRef ref) async {
    switch (segment) {
      case _LibrarySegment.decisions:
        // The Decision segment doubles as the home for Principle /
        // Assumption writers — they share authoring flow with Decision
        // (assumptions are referenced from decisions; principles
        // anchor them). A tiny chooser keeps the discovery path one
        // tap deep without 4 FABs.
        await _showDecisionFamilyChooser(context, ref);
      case _LibrarySegment.notes:
        await showKnowledgeCaptureSheet(context, ref);
      case _LibrarySegment.concepts:
        await showNewConceptSheet(context, ref);
      case _LibrarySegment.experiments:
        await showNewExperimentSheet(context, ref);
      case _LibrarySegment.routines:
        await showNewRoutineSheet(context, ref);
    }
  }
}

Future<void> _showDecisionFamilyChooser(
  BuildContext context,
  WidgetRef ref,
) async {
  await showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => _DecisionFamilyChooser(ref: ref),
  );
}

class _DecisionFamilyChooser extends StatelessWidget {
  const _DecisionFamilyChooser({required this.ref});
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tile(String label, String hint, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: FButton(
        variant: FButtonVariant.outline,
        onPress: () {
          Navigator.of(context).pop();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                hint,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AppSheet(
      title: l10n.knowledgeNewChooserTitle,
      subtitle: l10n.knowledgeNewChooserSubtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            'Decision',
            l10n.knowledgeNewDecisionHint,
            () => showNewDecisionSheet(context, ref),
          ),
          tile(
            'Principle',
            l10n.knowledgeNewPrincipleHint,
            () => showNewPrincipleSheet(context, ref),
          ),
          tile(
            'Assumption',
            l10n.knowledgeNewAssumptionHint,
            () => showNewAssumptionSheet(context, ref),
          ),
        ],
      ),
    );
  }
}

class _LibraryList extends ConsumerWidget {
  const _LibraryList({required this.segment, required this.query});
  final _LibrarySegment segment;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeLoadingState();
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        final l10n = AppLocalizations.of(context);
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(),
          error: (e, _) => KnowledgeErrorState(
            title: l10n.knowledgeLibraryLoadFailed('$e'),
            onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
          ),
          data: (repo) => switch (segment) {
            _LibrarySegment.decisions => _SegmentList<KnowledgeDecision>(
              stream: repo.watchDecisions(ownerUserId: owner),
              query: query,
              searchableText: (d) => [
                d.question,
                d.selectedLabel,
                d.rationaleMd,
                d.expectedOutcome,
              ].whereType<String>().join('\n'),
              emptyIcon: FLucideIcons.gitBranch,
              emptyTitle: l10n.knowledgeLibraryEmptyDecisionsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyDecisionsBody,
              tileBuilder: (context, d) => _buildDecisionTile(
                context,
                d,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.decision,
                    id: d.id,
                    title: d.question,
                  ),
                ),
              ),
            ),
            _LibrarySegment.notes => _SegmentList<KnowledgeNote>(
              stream: repo.watchNotes(ownerUserId: owner),
              query: query,
              searchableText: (n) => [
                n.title,
                n.bodyMd,
                n.projectTag,
                ...n.tags,
              ].whereType<String>().join('\n'),
              emptyIcon: FLucideIcons.fileText,
              emptyTitle: l10n.knowledgeLibraryEmptyNotesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyNotesBody,
              tileBuilder: (context, n) => _buildNoteTile(
                context,
                n,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.note,
                    id: n.id,
                    title: n.title.isEmpty
                        ? AppLocalizations.of(context).knowledgeUntitled
                        : n.title,
                  ),
                ),
              ),
            ),
            _LibrarySegment.concepts => _SegmentList<KnowledgeConcept>(
              stream: repo.watchConcepts(ownerUserId: owner),
              query: query,
              searchableText: (c) => [
                c.name,
                c.summaryMd,
                ...c.aliases,
              ].whereType<String>().join('\n'),
              emptyIcon: FLucideIcons.folderTree,
              emptyTitle: l10n.knowledgeLibraryEmptyConceptsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyConceptsBody,
              tileBuilder: (context, c) => _buildConceptTile(
                context,
                c,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.concept,
                    id: c.id,
                    title: c.name,
                  ),
                ),
              ),
            ),
            _LibrarySegment.experiments => _SegmentList<KnowledgeExperiment>(
              stream: repo.watchExperiments(ownerUserId: owner),
              query: query,
              searchableText: (e) => [
                e.hypothesis,
                e.methodMd,
                e.resultMd,
                ...e.metrics,
              ].whereType<String>().join('\n'),
              emptyIcon: FLucideIcons.flaskConical,
              emptyTitle: l10n.knowledgeLibraryEmptyExperimentsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyExperimentsBody,
              tileBuilder: (context, e) => _buildExperimentTile(
                context,
                e,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.experiment,
                    id: e.id,
                    title: e.hypothesis,
                  ),
                ),
              ),
            ),
            _LibrarySegment.routines => _SegmentList<KnowledgeRoutine>(
              stream: repo.watchRoutines(ownerUserId: owner),
              query: query,
              searchableText: (r) => [r.statement, r.scope].join('\n'),
              emptyIcon: FLucideIcons.calendarClock,
              emptyTitle: l10n.knowledgeLibraryEmptyRoutinesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyRoutinesBody,
              tileBuilder: (context, r) => _buildRoutineTile(
                context,
                r,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.routine,
                    id: r.id,
                    title: r.statement,
                  ),
                ),
              ),
            ),
          },
        );
      },
    );
  }
}

/// Generic Library segment list. Collapses the 4 per-type list
/// widgets that all did the same StreamBuilder → empty → ListView
/// dance, differing only in row layout (which is the [tileBuilder]
/// callback). Adding a 5th segment (Principle / Assumption browse)
/// is now a one-liner.
class _SegmentList<T> extends StatelessWidget {
  const _SegmentList({
    required this.stream,
    required this.query,
    required this.searchableText,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.tileBuilder,
  });

  final Stream<List<T>> stream;
  final String query;
  final String Function(T item) searchableText;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(BuildContext, T) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return KnowledgeErrorState(
            title: l10n.knowledgeLibraryLoadFailed('${snap.error}'),
          );
        }
        final items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return KnowledgeEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        }

        final visibleItems = normalizedQuery.isEmpty
            ? items
            : items
                  .where(
                    (item) => searchableText(
                      item,
                    ).toLowerCase().contains(normalizedQuery),
                  )
                  .toList(growable: false);

        if (visibleItems.isEmpty) {
          return KnowledgeEmptyState(
            icon: FLucideIcons.search,
            title: l10n.knowledgeLibrarySearchEmptyTitle,
            message: l10n.knowledgeLibrarySearchEmptyBody,
          );
        }

        return ListView.separated(
          itemCount: visibleItems.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) => tileBuilder(context, visibleItems[i]),
        );
      },
    );
  }
}

class _DeleteEntryButton extends StatelessWidget {
  const _DeleteEntryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FTooltip(
      tipBuilder: (_, _) =>
          Text(AppLocalizations.of(context).knowledgeLibraryDeleteTooltip),
      child: FButton.icon(
        variant: FButtonVariant.ghost,
        onPress: onPressed,
        child: Icon(
          FLucideIcons.trash2,
          size: AppIconSizes.sm,
          color: context.theme.colors.destructive,
        ),
      ),
    );
  }
}

Future<void> _deleteEntry({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeRepository repo,
  required KnowledgeEntryKind kind,
  required String id,
  required String title,
}) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(AppLocalizations.of(context).knowledgeLibraryDeleteTitle),
    body: Text(AppLocalizations.of(context).knowledgeLibraryDeleteBody(title)),
    confirmLabel: AppLocalizations.of(context).commonDelete,
    cancelLabel: AppLocalizations.of(context).commonCancel,
    destructive: true,
  );
  if (confirmed != true) return;

  try {
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    await repo.deleteEntry(
      kind: kind,
      id: id,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
        deletedAt: stamp.now,
      ),
    );
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).knowledgeDeletedToast,
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).knowledgeLibraryDeleteFailed('$e'),
      );
    }
  }
}

Widget _buildDecisionTile(
  BuildContext context,
  KnowledgeDecision d, {
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeDecisionDetail,
      pathParameters: {'id': d.id},
    ),
    title: d.question,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KnowledgeStatusLabel(label: d.status.wire),
        const SizedBox(width: AppSpacing.s4),
        deleteButton,
        const SizedBox(width: AppSpacing.s4),
        Icon(
          FLucideIcons.chevronRight,
          size: AppIconSizes.xs,
          color: colors.mutedForeground,
        ),
      ],
    ),
    children: [
      if (d.selectedLabel.isNotEmpty)
        Text(
          d.selectedLabel,
          style: typography.sm.copyWith(color: colors.primary),
        ),
      if (d.rationaleMd.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s4),
        Text(
          knowledgeExcerpt(d.rationaleMd),
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
      ],
    ],
  );
}

Widget _buildNoteTile(
  BuildContext context,
  KnowledgeNote n, {
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  return KnowledgeSection.item(
    title: n.title.isEmpty ? l10n.knowledgeUntitled : n.title,
    trailing: deleteButton,
    children: [
      if (n.bodyMd.isNotEmpty)
        Text(
          knowledgeExcerpt(n.bodyMd),
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
    ],
  );
}

Widget _buildConceptTile(
  BuildContext context,
  KnowledgeConcept c, {
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'concept', 'id': c.id},
    ),
    title: c.name,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        deleteButton,
        const SizedBox(width: AppSpacing.s4),
        Icon(
          FLucideIcons.chevronRight,
          size: AppIconSizes.xs,
          color: colors.mutedForeground,
        ),
      ],
    ),
    children: [
      if (c.summaryMd.isNotEmpty)
        Text(
          knowledgeExcerpt(c.summaryMd),
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
    ],
  );
}

Widget _buildExperimentTile(
  BuildContext context,
  KnowledgeExperiment e, {
  required Widget deleteButton,
}) {
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'experiment', 'id': e.id},
    ),
    title: e.hypothesis,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KnowledgeStatusLabel(label: e.status.wire),
        const SizedBox(width: AppSpacing.s4),
        deleteButton,
        const SizedBox(width: AppSpacing.s4),
        Icon(
          FLucideIcons.chevronRight,
          size: AppIconSizes.xs,
          color: colors.mutedForeground,
        ),
      ],
    ),
    children: const [],
  );
}

Widget _buildRoutineTile(
  BuildContext context,
  KnowledgeRoutine r, {
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final days = r.daysUntilDue(now);
  final dueLabel = days < 0
      ? l10n.knowledgeRoutineOverdueDays(-days)
      : days == 0
      ? l10n.knowledgeRoutineDueToday
      : l10n.knowledgeRoutineDueInDays(days);
  final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
  return KnowledgeSection.item(
    title: r.statement,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KnowledgeStatusLabel(label: r.status.wire),
        const SizedBox(width: AppSpacing.s4),
        deleteButton,
      ],
    ),
    children: [
      Text(
        l10n.knowledgeRoutineLibraryMeta(dueLabel, r.intervalDays, r.scope),
        style: typography.sm.copyWith(color: dueColor),
      ),
    ],
  );
}
