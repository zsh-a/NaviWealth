/// KnowledgeOS Library tab (`docs/knowledgeos-domain.md` §5).
///
/// Library segments for the KnowledgeOS object families. Decisions surface a
/// status badge per the 7-state lifecycle in §9. Forui-only — Forui + Flutter
/// widgets so the page renders correctly inside any scope.
library;

import 'dart:async';

import 'package:flutter/services.dart';
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
import '../domain/knowledge_search_suggestions.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

enum _LibrarySegment {
  decisions,
  principles,
  assumptions,
  notes,
  concepts,
  experiments,
  routines,
}

enum KnowledgeLibraryDateFilter { all, today, week, month, outsideMonth }

const String _kKnowledgeLibrarySearchHistoryPrefsKey =
    'knowledge.library.search_history.v1';
const int _kKnowledgeLibrarySearchHistoryLimit = 6;

List<String> _normalizedSearchHistory(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    final value = item.trim();
    if (value.length < 2) continue;
    final key = value.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(value);
    if (out.length >= _kKnowledgeLibrarySearchHistoryLimit) break;
  }
  return out;
}

String _segmentLabel(AppLocalizations l10n, _LibrarySegment segment) {
  return switch (segment) {
    _LibrarySegment.decisions => l10n.knowledgeSegmentDecisions,
    _LibrarySegment.principles => l10n.knowledgeSegmentPrinciples,
    _LibrarySegment.assumptions => l10n.knowledgeSegmentAssumptions,
    _LibrarySegment.notes => l10n.knowledgeSegmentNotes,
    _LibrarySegment.concepts => l10n.knowledgeSegmentConcepts,
    _LibrarySegment.experiments => l10n.knowledgeSegmentExperiments,
    _LibrarySegment.routines => l10n.knowledgeSegmentRoutines,
  };
}

String _dateFilterLabel(
  AppLocalizations l10n,
  KnowledgeLibraryDateFilter filter,
) {
  return switch (filter) {
    KnowledgeLibraryDateFilter.all => l10n.knowledgeLibraryDateFilterAll,
    KnowledgeLibraryDateFilter.today => l10n.knowledgeLibraryDateFilterToday,
    KnowledgeLibraryDateFilter.week => l10n.knowledgeLibraryDateFilterWeek,
    KnowledgeLibraryDateFilter.month => l10n.knowledgeLibraryDateFilterMonth,
    KnowledgeLibraryDateFilter.outsideMonth =>
      l10n.knowledgeLibraryDateFilterOutsideMonth,
  };
}

bool matchesKnowledgeLibraryDateFilter(
  DateTime date,
  KnowledgeLibraryDateFilter filter,
  DateTime now,
) {
  if (filter == KnowledgeLibraryDateFilter.all) return true;
  final dateLocal = date.toLocal();
  final nowLocal = now.toLocal();
  final localDate = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
  final localNow = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final days = localDate.difference(localNow).inDays.abs();
  return switch (filter) {
    KnowledgeLibraryDateFilter.all => true,
    KnowledgeLibraryDateFilter.today => days == 0,
    KnowledgeLibraryDateFilter.week => days <= 7,
    KnowledgeLibraryDateFilter.month => days <= 30,
    KnowledgeLibraryDateFilter.outsideMonth => days > 30,
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
  final _searchFocus = FocusNode();
  final List<String> _searchHistory = <String>[];
  bool _fabHidden = false;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _loadSearchHistory() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored =
        prefs.getStringList(_kKnowledgeLibrarySearchHistoryPrefsKey) ??
        const <String>[];
    _searchHistory
      ..clear()
      ..addAll(_normalizedSearchHistory(stored));
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commitSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commitSearch([String? raw]) {
    final query = (raw ?? _searchCtrl.text).trim();
    if (query.length < 2) return;
    setState(() {
      _searchHistory
        ..clear()
        ..addAll(_normalizedSearchHistory(<String>[query, ..._searchHistory]));
    });
    unawaited(_persistSearchHistory());
  }

  Future<void> _persistSearchHistory() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(
      _kKnowledgeLibrarySearchHistoryPrefsKey,
      List<String>.unmodifiable(_searchHistory),
    );
  }

  void _clearSearchHistory() {
    if (_searchHistory.isEmpty) return;
    setState(_searchHistory.clear);
    unawaited(_persistSearchHistory());
  }

  void _applySearch(String query) {
    _searchCtrl.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _commitSearch(query);
    _searchFocus.requestFocus();
  }

  bool _onScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final delta = notification.scrollDelta ?? 0;
    if (delta > 4 && !_fabHidden) {
      setState(() => _fabHidden = true);
    } else if (delta < -4 && _fabHidden) {
      setState(() => _fabHidden = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeLibraryTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScrollUpdate,
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
                      onChanged: (s) => setState(() {
                        _segment = s;
                        _fabHidden = false;
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Row(
                      children: [
                        Expanded(
                          child: Focus(
                            onKeyEvent: _onSearchKey,
                            child: FTextField(
                              control: FTextFieldControl.managed(
                                controller: _searchCtrl,
                              ),
                              focusNode: _searchFocus,
                              textInputAction: TextInputAction.search,
                              prefixBuilder: (_, _, _) => const Padding(
                                padding: EdgeInsetsDirectional.only(
                                  start: 12,
                                  end: 8,
                                ),
                                child: Icon(
                                  FLucideIcons.search,
                                  size: AppIconSizes.h18,
                                ),
                              ),
                              hint: l10n.knowledgeLibrarySearchHint,
                            ),
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
                        searchHistory: _searchHistory,
                        onSearchSelected: _applySearch,
                        onSearchHistoryClear: _clearSearchHistory,
                        onRefresh: () => _refreshKnowledgeRepository(ref),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: KnowledgeFloatingActionMotion(
              hidden: _fabHidden,
              child: _NewObjectButton(segment: _segment),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forui-native floating action affordance for the active Library segment.
class _NewObjectButton extends ConsumerWidget {
  const _NewObjectButton({required this.segment});

  final _LibrarySegment segment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = switch (segment) {
      _LibrarySegment.decisions => l10n.knowledgeNewDecision,
      _LibrarySegment.principles => l10n.knowledgeNewPrinciple,
      _LibrarySegment.assumptions => l10n.knowledgeNewAssumption,
      _LibrarySegment.notes => l10n.knowledgeNewNote,
      _LibrarySegment.concepts => l10n.knowledgeNewConcept,
      _LibrarySegment.experiments => l10n.knowledgeNewExperiment,
      _LibrarySegment.routines => l10n.knowledgeNewRoutine,
    };
    return KnowledgeFloatingActionSurface(
      child: FButton(
        prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
        onPress: () => _onPress(context, ref),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Text(label, key: ValueKey<String>(label)),
        ),
      ),
    );
  }

  Future<void> _onPress(BuildContext context, WidgetRef ref) async {
    switch (segment) {
      case _LibrarySegment.decisions:
        await showNewDecisionSheet(context, ref);
      case _LibrarySegment.principles:
        await showNewPrincipleSheet(context, ref);
      case _LibrarySegment.assumptions:
        await showNewAssumptionSheet(context, ref);
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

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.segment,
    required this.query,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    required this.onRefresh,
  });

  final _LibrarySegment segment;
  final String query;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final Future<void> Function() onRefresh;

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
              searchSuggestions: (context, d) => [
                d.status.wire,
                d.selectedLabel,
                d.reviewDate == null
                    ? null
                    : knowledgeDate(context, d.reviewDate!),
              ].whereType<String>().toList(growable: false),
              filterFacets: (_, _) => const <String>[],
              dateOf: (d) => d.decidedAt,
              emptyIcon: FLucideIcons.gitBranch,
              emptyTitle: l10n.knowledgeLibraryEmptyDecisionsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyDecisionsBody,
              statusOf: (d) => d.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, d, query) => _buildDecisionTile(
                context,
                d,
                query: query,
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
            _LibrarySegment.principles => _SegmentList<KnowledgePrinciple>(
              stream: repo.watchPrinciples(ownerUserId: owner),
              query: query,
              searchableText: (p) => [
                p.statement,
                p.rationaleMd,
                p.scope,
                p.status.wire,
              ].join('\n'),
              searchSuggestions: (_, p) =>
                  [p.status.wire, p.scope].toList(growable: false),
              filterFacets: (_, p) => [p.scope],
              dateOf: (p) => p.declaredAt,
              emptyIcon: FLucideIcons.badgeCheck,
              emptyTitle: l10n.knowledgeLibraryEmptyPrinciplesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyPrinciplesBody,
              statusOf: (p) => p.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, p, query) => _buildPrincipleTile(
                context,
                p,
                query: query,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.principle,
                    id: p.id,
                    title: p.statement,
                  ),
                ),
              ),
            ),
            _LibrarySegment.assumptions => _SegmentList<KnowledgeAssumption>(
              stream: repo.watchAssumptions(ownerUserId: owner),
              query: query,
              searchableText: (a) => [
                a.statement,
                a.scope,
                a.status.wire,
                a.confidence.toStringAsFixed(2),
              ].join('\n'),
              searchSuggestions: (_, a) => [
                a.status.wire,
                a.scope,
                a.confidence.toStringAsFixed(2),
              ],
              filterFacets: (_, a) => [a.scope],
              dateOf: (a) => a.declaredAt,
              emptyIcon: FLucideIcons.lightbulb,
              emptyTitle: l10n.knowledgeLibraryEmptyAssumptionsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyAssumptionsBody,
              statusOf: (a) => a.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, a, query) => _buildAssumptionTile(
                context,
                a,
                query: query,
                deleteButton: _DeleteEntryButton(
                  onPressed: () => _deleteEntry(
                    context: context,
                    ref: ref,
                    repo: repo,
                    kind: KnowledgeEntryKind.assumption,
                    id: a.id,
                    title: a.statement,
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
              searchSuggestions: (_, n) => [
                n.projectTag,
                ...n.tags,
              ].whereType<String>().toList(growable: false),
              filterFacets: (_, n) =>
                  [n.projectTag, ...n.tags].whereType<String>().toList(),
              dateOf: (n) => n.createdAt,
              emptyIcon: FLucideIcons.fileText,
              emptyTitle: l10n.knowledgeLibraryEmptyNotesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyNotesBody,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, n, query) => _buildNoteTile(
                context,
                n,
                query: query,
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
              searchSuggestions: (_, c) =>
                  [c.name, ...c.aliases].toList(growable: false),
              filterFacets: (_, c) => [...c.aliases],
              dateOf: (c) => c.createdAt,
              emptyIcon: FLucideIcons.folderTree,
              emptyTitle: l10n.knowledgeLibraryEmptyConceptsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyConceptsBody,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, c, query) => _buildConceptTile(
                context,
                c,
                query: query,
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
              searchSuggestions: (_, e) =>
                  [e.status.wire, ...e.metrics].toList(growable: false),
              filterFacets: (_, e) => [...e.metrics],
              dateOf: (e) => e.startedAt,
              emptyIcon: FLucideIcons.flaskConical,
              emptyTitle: l10n.knowledgeLibraryEmptyExperimentsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyExperimentsBody,
              statusOf: (e) => e.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, e, query) => _buildExperimentTile(
                context,
                e,
                query: query,
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
              searchSuggestions: (_, r) =>
                  [r.status.wire, r.scope].toList(growable: false),
              filterFacets: (_, r) => [r.scope],
              dateOf: (r) => r.nextDueAt,
              emptyIcon: FLucideIcons.calendarClock,
              emptyTitle: l10n.knowledgeLibraryEmptyRoutinesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyRoutinesBody,
              statusOf: (r) => r.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onRefresh: onRefresh,
              tileBuilder: (context, r, query) => _buildRoutineTile(
                context,
                r,
                query: query,
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
class _SegmentList<T> extends StatefulWidget {
  const _SegmentList({
    required this.stream,
    required this.query,
    required this.searchableText,
    required this.searchSuggestions,
    required this.filterFacets,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.tileBuilder,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    required this.onRefresh,
    required this.dateOf,
    this.statusOf,
  });

  final Stream<List<T>> stream;
  final String query;
  final String Function(T item) searchableText;
  final List<String> Function(BuildContext context, T item) searchSuggestions;
  final List<String> Function(BuildContext context, T item) filterFacets;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(BuildContext, T, String query) tileBuilder;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final Future<void> Function() onRefresh;
  final DateTime Function(T item)? dateOf;
  final String Function(T item)? statusOf;

  @override
  State<_SegmentList<T>> createState() => _SegmentListState<T>();
}

class _SegmentListState<T> extends State<_SegmentList<T>> {
  String? _statusFilter;
  String? _facetFilter;
  KnowledgeLibraryDateFilter _dateFilter = KnowledgeLibraryDateFilter.all;

  @override
  void didUpdateWidget(covariant _SegmentList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emptyTitle != widget.emptyTitle) {
      _statusFilter = null;
      _facetFilter = null;
      _dateFilter = KnowledgeLibraryDateFilter.all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final normalizedQuery = widget.query.trim().toLowerCase();
    return StreamBuilder<List<T>>(
      stream: widget.stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return KnowledgeErrorState(
            title: l10n.knowledgeLibraryLoadFailed('${snap.error}'),
          );
        }
        final items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return KnowledgeEmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            message: widget.emptyMessage,
          );
        }

        final statusOf = widget.statusOf;
        final statuses = <String>[];
        if (statusOf != null) {
          statuses.addAll(items.map(statusOf).toSet());
          statuses.sort();
        }
        if (_statusFilter != null && !statuses.contains(_statusFilter)) {
          _statusFilter = null;
        }
        final facets = _facetsFor(context, items);
        if (_facetFilter != null && !facets.contains(_facetFilter)) {
          _facetFilter = null;
        }
        final searchAssist = _SearchAssistRow(
          history: widget.searchHistory,
          suggestions: _suggestionsFor(context, items, normalizedQuery),
          query: normalizedQuery,
          onSelected: widget.onSearchSelected,
          onHistoryClear: widget.onSearchHistoryClear,
        );

        final statusFilteredItems = _statusFilter == null || statusOf == null
            ? items
            : items
                  .where((item) => statusOf(item) == _statusFilter)
                  .toList(growable: false);
        final facetedItems = _facetFilter == null
            ? statusFilteredItems
            : statusFilteredItems
                  .where(
                    (item) => widget
                        .filterFacets(context, item)
                        .contains(_facetFilter),
                  )
                  .toList(growable: false);
        final dateOf = widget.dateOf;
        final dateFilteredItems =
            dateOf == null || _dateFilter == KnowledgeLibraryDateFilter.all
            ? facetedItems
            : facetedItems
                  .where(
                    (item) => matchesKnowledgeLibraryDateFilter(
                      dateOf(item),
                      _dateFilter,
                      DateTime.now(),
                    ),
                  )
                  .toList(growable: false);

        final visibleItems = normalizedQuery.isEmpty
            ? dateFilteredItems
            : dateFilteredItems
                  .where(
                    (item) => widget
                        .searchableText(item)
                        .toLowerCase()
                        .contains(normalizedQuery),
                  )
                  .toList(growable: false);

        if (visibleItems.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchAssist,
              if (searchAssist.hasContent)
                const SizedBox(height: AppSpacing.s8),
              if (statuses.length > 1) ...[
                _FilterChipRow(
                  icon: FLucideIcons.listFilter,
                  values: statuses,
                  selected: _statusFilter,
                  onChanged: (status) => setState(() => _statusFilter = status),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (dateOf != null) ...[
                _DateFilterChipRow(
                  selected: _dateFilter,
                  onChanged: (filter) => setState(() => _dateFilter = filter),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (facets.isNotEmpty) ...[
                _FilterChipRow(
                  icon: FLucideIcons.tags,
                  values: facets,
                  selected: _facetFilter,
                  onChanged: (facet) => setState(() => _facetFilter = facet),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              Expanded(
                child: KnowledgeEmptyState(
                  icon: FLucideIcons.search,
                  title: l10n.knowledgeLibrarySearchEmptyTitle,
                  message: l10n.knowledgeLibrarySearchEmptyBody,
                ),
              ),
            ],
          );
        }

        final list = KnowledgePullToRefresh(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) =>
                widget.tileBuilder(context, visibleItems[i], widget.query),
          ),
        );
        final filterRows = <Widget>[
          if (statuses.length > 1)
            _FilterChipRow(
              icon: FLucideIcons.listFilter,
              values: statuses,
              selected: _statusFilter,
              onChanged: (status) => setState(() => _statusFilter = status),
            ),
          if (dateOf != null)
            _DateFilterChipRow(
              selected: _dateFilter,
              onChanged: (filter) => setState(() => _dateFilter = filter),
            ),
          if (facets.isNotEmpty)
            _FilterChipRow(
              icon: FLucideIcons.tags,
              values: facets,
              selected: _facetFilter,
              onChanged: (facet) => setState(() => _facetFilter = facet),
            ),
        ];
        if (filterRows.isEmpty) {
          if (!searchAssist.hasContent) return list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchAssist,
              const SizedBox(height: AppSpacing.s8),
              Expanded(child: list),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchAssist,
            if (searchAssist.hasContent) const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < filterRows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s8),
              filterRows[i],
            ],
            if (filterRows.isNotEmpty) const SizedBox(height: AppSpacing.s12),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  List<String> _suggestionsFor(
    BuildContext context,
    List<T> items,
    String query,
  ) {
    return rankKnowledgeSearchSuggestions(
      weightedSuggestions: [
        for (final item in items) ...widget.searchSuggestions(context, item),
      ],
      searchableTexts: [for (final item in items) widget.searchableText(item)],
      query: query,
    );
  }

  List<String> _facetsFor(BuildContext context, List<T> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      for (final raw in widget.filterFacets(context, item)) {
        final value = raw.trim();
        if (value.length < 2) continue;
        if (!seen.add(value.toLowerCase())) continue;
        out.add(value);
        if (out.length >= 12) return out;
      }
    }
    out.sort();
    return out;
  }
}

class _SearchAssistRow extends StatelessWidget {
  const _SearchAssistRow({
    required this.history,
    required this.suggestions,
    required this.query,
    required this.onSelected,
    required this.onHistoryClear,
  });

  final List<String> history;
  final List<String> suggestions;
  final String query;
  final ValueChanged<String> onSelected;
  final VoidCallback onHistoryClear;

  bool get hasContent =>
      suggestions.isNotEmpty ||
      (query.isEmpty
          ? history.isNotEmpty
          : history.any((item) => item.toLowerCase().contains(query)));

  @override
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final visibleHistory = query.isEmpty
        ? history
        : history
              .where((item) => item.toLowerCase().contains(query))
              .toList(growable: false);
    final chips = <Widget>[
      if (visibleHistory.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchRecent,
          values: visibleHistory,
          icon: FLucideIcons.history,
          onSelected: onSelected,
          onClear: query.isEmpty ? onHistoryClear : null,
        ),
      if (suggestions.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchSuggestions,
          values: suggestions,
          icon: FLucideIcons.sparkles,
          onSelected: onSelected,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s8),
          chips[i],
        ],
      ],
    );
  }
}

class _SearchAssistGroup extends StatelessWidget {
  const _SearchAssistGroup({
    required this.label,
    required this.values,
    required this.icon,
    required this.onSelected,
    this.onClear,
  });

  final String label;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final visibleValues = values.take(6).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s4),
            Text(
              label,
              style: typography.xs.copyWith(color: colors.mutedForeground),
            ),
            if (onClear != null) ...[
              const SizedBox(width: AppSpacing.s4),
              FButton.icon(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                onPress: onClear,
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < visibleValues.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.s6),
                  _SearchAssistChip(
                    value: visibleValues[i],
                    onPress: () => onSelected(visibleValues[i]),
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

class _SearchAssistChip extends StatelessWidget {
  const _SearchAssistChip({required this.value, required this.onPress});

  final String value;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return FTappable(
      onPress: onPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 128),
            child: Text(
              value,
              style: typography.xs.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.icon,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget chip(String label, String? value) {
      final active = selected == value;
      return FButton(
        variant: active ? FButtonVariant.primary : FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        onPress: () => onChanged(value),
        child: Text(label),
      );
    }

    return Row(
      children: [
        Icon(
          icon,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(l10n.knowledgeLibraryFilterAll, null),
                for (final value in values) ...[
                  const SizedBox(width: AppSpacing.s8),
                  chip(value, value),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DateFilterChipRow extends StatelessWidget {
  const _DateFilterChipRow({required this.selected, required this.onChanged});

  final KnowledgeLibraryDateFilter selected;
  final ValueChanged<KnowledgeLibraryDateFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget chip(KnowledgeLibraryDateFilter filter) {
      final active = selected == filter;
      return FButton(
        variant: active ? FButtonVariant.primary : FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        onPress: () => onChanged(filter),
        child: Text(_dateFilterLabel(l10n, filter)),
      );
    }

    return Row(
      children: [
        Icon(
          FLucideIcons.calendarDays,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in KnowledgeLibraryDateFilter.values) ...[
                  if (filter != KnowledgeLibraryDateFilter.values.first)
                    const SizedBox(width: AppSpacing.s8),
                  chip(filter),
                ],
              ],
            ),
          ),
        ),
      ],
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

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  await ref.read(knowledgeRepositoryProvider.future);
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
  required String query,
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeDecisionDetail,
      pathParameters: {'id': d.id},
    ),
    children: [
      _LibraryTileHeader(
        title: d.question,
        query: query,
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
      ),
      if (d.selectedLabel.isNotEmpty)
        KnowledgeHighlightedText(
          text: d.selectedLabel,
          query: query,
          style: typography.sm.copyWith(color: colors.primary),
        ),
      if (d.rationaleMd.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s4),
        KnowledgeHighlightedText(
          text: knowledgeExcerpt(d.rationaleMd),
          query: query,
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
      ],
    ],
  );
}

Widget _buildNoteTile(
  BuildContext context,
  KnowledgeNote n, {
  required String query,
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'note', 'id': n.id},
    ),
    children: [
      _LibraryTileHeader(
        title: n.title.isEmpty ? l10n.knowledgeUntitled : n.title,
        query: query,
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
      ),
      if (n.bodyMd.isNotEmpty)
        KnowledgeHighlightedText(
          text: knowledgeExcerpt(n.bodyMd),
          query: query,
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
    ],
  );
}

Widget _buildPrincipleTile(
  BuildContext context,
  KnowledgePrinciple p, {
  required String query,
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'principle', 'id': p.id},
    ),
    children: [
      _LibraryTileHeader(
        title: p.statement,
        query: query,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KnowledgeStatusLabel(label: p.status.wire),
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
      ),
      Text(
        l10n.knowledgeDetailScope(p.scope),
        style: typography.sm.copyWith(color: colors.mutedForeground),
      ),
      if (p.rationaleMd.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s4),
        KnowledgeHighlightedText(
          text: knowledgeExcerpt(p.rationaleMd),
          query: query,
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
      ],
    ],
  );
}

Widget _buildAssumptionTile(
  BuildContext context,
  KnowledgeAssumption a, {
  required String query,
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'assumption', 'id': a.id},
    ),
    children: [
      _LibraryTileHeader(
        title: a.statement,
        query: query,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KnowledgeStatusLabel(label: a.status.wire),
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
      ),
      Text(
        l10n.knowledgeDetailConfidenceScope(
          a.confidence.toStringAsFixed(2),
          a.scope,
        ),
        style: typography.sm.copyWith(color: colors.mutedForeground),
      ),
    ],
  );
}

Widget _buildConceptTile(
  BuildContext context,
  KnowledgeConcept c, {
  required String query,
  required Widget deleteButton,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'concept', 'id': c.id},
    ),
    children: [
      _LibraryTileHeader(
        title: c.name,
        query: query,
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
      ),
      if (c.summaryMd.isNotEmpty)
        KnowledgeHighlightedText(
          text: knowledgeExcerpt(c.summaryMd),
          query: query,
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
    ],
  );
}

Widget _buildExperimentTile(
  BuildContext context,
  KnowledgeExperiment e, {
  required String query,
  required Widget deleteButton,
}) {
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'experiment', 'id': e.id},
    ),
    children: [
      _LibraryTileHeader(
        title: e.hypothesis,
        query: query,
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
      ),
    ],
  );
}

Widget _buildRoutineTile(
  BuildContext context,
  KnowledgeRoutine r, {
  required String query,
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
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'routine', 'id': r.id},
    ),
    children: [
      _LibraryTileHeader(
        title: r.statement,
        query: query,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KnowledgeStatusLabel(label: r.status.wire),
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
      ),
      Text(
        l10n.knowledgeRoutineLibraryMeta(dueLabel, r.intervalDays, r.scope),
        style: typography.sm.copyWith(color: dueColor),
      ),
    ],
  );
}

class _LibraryTileHeader extends StatelessWidget {
  const _LibraryTileHeader({
    required this.title,
    required this.query,
    required this.trailing,
  });

  final String title;
  final String query;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: KnowledgeHighlightedText(
              text: title,
              query: query,
              style: context.theme.typography.md.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          trailing,
        ],
      ),
    );
  }
}
