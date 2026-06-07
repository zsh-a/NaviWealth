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

IconData _segmentIcon(_LibrarySegment segment) => switch (segment) {
  _LibrarySegment.decisions => FLucideIcons.gitBranch,
  _LibrarySegment.principles => FLucideIcons.badgeCheck,
  _LibrarySegment.assumptions => FLucideIcons.lightbulb,
  _LibrarySegment.notes => FLucideIcons.fileText,
  _LibrarySegment.concepts => FLucideIcons.folderTree,
  _LibrarySegment.experiments => FLucideIcons.flaskConical,
  _LibrarySegment.routines => FLucideIcons.calendarClock,
};

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

/// Weighted search: ranks prefix matches above substring matches, and
/// suggestion-field matches above full-text matches. Returns items
/// sorted by relevance (best first), filtered to only matching items.
List<T> _rankedSearch<T>({
  required List<T> items,
  required String query,
  required String Function(T item) searchableText,
  required List<String> Function(T item) searchSuggestions,
}) {
  final scored = <(T, double)>[];
  for (final item in items) {
    final score = _searchRelevanceScore(
      query: query,
      fullText: searchableText(item),
      suggestions: searchSuggestions(item),
    );
    if (score > 0) scored.add((item, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList(growable: false);
}

/// Returns a relevance score > 0 if the item matches, 0 otherwise.
/// Higher is better.
double _searchRelevanceScore({
  required String query,
  required String fullText,
  required List<String> suggestions,
}) {
  final lowerQuery = query.toLowerCase();
  final lowerFull = fullText.toLowerCase();

  // No match at all.
  if (!lowerFull.contains(lowerQuery)) return 0;

  double score = 1; // Base: substring match in full text.

  // Boost for matching in suggestion fields (title, status, tags).
  for (final s in suggestions) {
    final lower = s.toLowerCase();
    if (lower.contains(lowerQuery)) {
      score += 2;
      if (lower.startsWith(lowerQuery)) score += 3;
    }
  }

  // Boost for prefix match in full text.
  if (lowerFull.startsWith(lowerQuery)) score += 2;

  return score;
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

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage>
    with KnowledgeFabScrollHideMixin {
  _LibrarySegment _segment = _LibrarySegment.decisions;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final List<String> _searchHistory = <String>[];

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

  void _removeSearchHistoryItem(String value) {
    setState(() => _searchHistory.remove(value));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeLibraryTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: onScrollUpdate,
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
                    _LibraryTabBar(
                      selected: _segment,
                      onChanged: (s) => setState(() {
                        _segment = s;
                        fabHidden = false;
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
                                  start: AppSpacing.s12,
                                  end: AppSpacing.s8,
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
                        onSearchHistoryItemDelete: _removeSearchHistoryItem,
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
              hidden: fabHidden,
              child: _LibraryCreateFab(activeSegment: _segment),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon-only FAB that opens the knowledge type picker sheet.
class _LibraryCreateFab extends ConsumerWidget {
  const _LibraryCreateFab({required this.activeSegment});

  final _LibrarySegment activeSegment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KnowledgeFloatingActionSurface(
      child: FButton(
        variant: FButtonVariant.ghost,
        prefix: const Icon(
          FLucideIcons.plus,
          size: AppIconSizes.sm,
          color: Color(0xFFFFFFFF),
        ),
        onPress: () => _openCreateSheet(context, ref),
        child: const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _openCreateSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final activeLabel = _segmentLabel(l10n, activeSegment);
    final options = [
      KnowledgeCreateOption(
        icon: FLucideIcons.gitBranch,
        label: l10n.knowledgeNewDecision,
        onSelected: () => showNewDecisionSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.badgeCheck,
        label: l10n.knowledgeNewPrinciple,
        onSelected: () => showNewPrincipleSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.lightbulb,
        label: l10n.knowledgeNewAssumption,
        onSelected: () => showNewAssumptionSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.fileText,
        label: l10n.knowledgeNewNote,
        onSelected: () => showKnowledgeCaptureSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.folderTree,
        label: l10n.knowledgeNewConcept,
        onSelected: () => showNewConceptSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.flaskConical,
        label: l10n.knowledgeNewExperiment,
        onSelected: () => showNewExperimentSheet(context, ref),
      ),
      KnowledgeCreateOption(
        icon: FLucideIcons.calendarClock,
        label: l10n.knowledgeNewRoutine,
        onSelected: () => showNewRoutineSheet(context, ref),
      ),
    ];
    await showKnowledgeCreateSheet(
      context,
      options: options,
      activeLabel: activeLabel,
    );
  }
}

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.segment,
    required this.query,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    required this.onSearchHistoryItemDelete,
    required this.onRefresh,
  });

  final _LibrarySegment segment;
  final String query;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final ValueChanged<String> onSearchHistoryItemDelete;
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, d, query) => _buildDecisionTile(
                context,
                d,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.decision,
                  id: d.id,
                  title: d.question,
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, p, query) => _buildPrincipleTile(
                context,
                p,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.principle,
                  id: p.id,
                  title: p.statement,
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, a, query) => _buildAssumptionTile(
                context,
                a,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.assumption,
                  id: a.id,
                  title: a.statement,
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, n, query) => _buildNoteTile(
                context,
                n,
                query: query,
                onDelete: () => _deleteEntry(
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, c, query) => _buildConceptTile(
                context,
                c,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.concept,
                  id: c.id,
                  title: c.name,
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, e, query) => _buildExperimentTile(
                context,
                e,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.experiment,
                  id: e.id,
                  title: e.hypothesis,
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
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
              tileBuilder: (context, r, query) => _buildRoutineTile(
                context,
                r,
                query: query,
                onDelete: () => _deleteEntry(
                  context: context,
                  ref: ref,
                  repo: repo,
                  kind: KnowledgeEntryKind.routine,
                  id: r.id,
                  title: r.statement,
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
    this.onSearchHistoryItemDelete,
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
  final ValueChanged<String>? onSearchHistoryItemDelete;
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
          onHistoryItemDelete: widget.onSearchHistoryItemDelete,
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
            : _rankedSearch(
                items: dateFilteredItems,
                query: normalizedQuery,
                searchableText: widget.searchableText,
                searchSuggestions: (item) =>
                    widget.searchSuggestions(context, item),
              );

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
    this.onHistoryItemDelete,
  });

  final List<String> history;
  final List<String> suggestions;
  final String query;
  final ValueChanged<String> onSelected;
  final VoidCallback onHistoryClear;
  final ValueChanged<String>? onHistoryItemDelete;

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
          onItemDelete: onHistoryItemDelete,
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
    this.onItemDelete,
  });

  final String label;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final VoidCallback? onClear;
  final ValueChanged<String>? onItemDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
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
              style: context.captionStyle,
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
                    onDelete: onItemDelete != null
                        ? () => onItemDelete!(visibleValues[i])
                        : null,
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
  const _SearchAssistChip({
    required this.value,
    required this.onPress,
    this.onDelete,
  });

  final String value;
  final VoidCallback onPress;
  final VoidCallback? onDelete;

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
          padding: EdgeInsets.only(
            left: AppSpacing.s8,
            right: onDelete != null ? AppSpacing.s4 : AppSpacing.s8,
            top: AppSpacing.s4,
            bottom: AppSpacing.s4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  value,
                  style: typography.xs.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: AppSpacing.s2),
                GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s2),
                    child: Icon(
                      FLucideIcons.x,
                      size: AppIconSizes.xs,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ],
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
    return Row(
      children: [
        Icon(
          icon,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: l10n.knowledgeLibraryFilterAll,
                  active: selected == null,
                  onTap: () => onChanged(null),
                ),
                for (final value in values)
                  _FilterPill(
                    label: value,
                    active: selected == value,
                    onTap: () => onChanged(value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Lightweight pill chip for filter rows. Compact padding, muted
/// border, no heavy button chrome — scannable without dominating
/// the viewport.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s4),
      child: FTappable(
        onPress: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standardDecelerate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: AppOpacity.subtle)
                : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: active
                  ? colors.primary.withValues(alpha: AppOpacity.light)
                  : colors.border,
            ),
          ),
          child: Text(
            label,
            style: typography.xs.copyWith(
              color: active ? colors.primary : colors.mutedForeground,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
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
    return Row(
      children: [
        Icon(
          FLucideIcons.calendarDays,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in KnowledgeLibraryDateFilter.values)
                  _FilterPill(
                    label: _dateFilterLabel(l10n, filter),
                    active: selected == filter,
                    onTap: () => onChanged(filter),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontally scrollable tab bar for the 7 Library segments.
///
/// Replaces [SegmentedRow] which crammed all 7 labels into a single
/// non-scrollable row — unreadable on small screens. Each tab is a
/// compact pill: icon-only when unselected to save space, expanding
/// to icon + label for the active segment.
class _LibraryTabBar extends StatelessWidget {
  const _LibraryTabBar({required this.selected, required this.onChanged});

  final _LibrarySegment selected;
  final ValueChanged<_LibrarySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _LibrarySegment.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s6),
        itemBuilder: (context, i) {
          final segment = _LibrarySegment.values[i];
          final active = segment == selected;
          return FTappable(
            onPress: () => onChanged(segment),
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standardDecelerate,
              padding: EdgeInsets.symmetric(
                horizontal: active ? AppSpacing.s12 : AppSpacing.s8,
                vertical: AppSpacing.s6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? colors.primary.withValues(alpha: AppOpacity.subtle)
                    : colors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: AppOpacity.light)
                      : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _segmentIcon(segment),
                    size: AppIconSizes.xs,
                    color: active ? colors.primary : colors.mutedForeground,
                  ),
                  if (active) ...[
                    const SizedBox(width: AppSpacing.s4),
                    Text(
                      _segmentLabel(l10n, segment),
                      style: typography.xs.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
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

/// Unified Library tile shell. Encodes the shared layout:
/// `KnowledgeSection.item` → type icon + `_LibraryTileHeader` (title
/// + trailing row with optional status badge + chevron) → optional subtitle.
Widget _buildLibraryTile(
  BuildContext context, {
  required String title,
  required String query,
  required VoidCallback onPress,
  required VoidCallback onDelete,
  IconData? typeIcon,
  Color? typeColor,
  String? statusBadge,
  List<Widget> subtitle = const <Widget>[],
}) {
  final colors = context.theme.colors;
  return Dismissible(
    key: ValueKey<String>('lib-tile-$title'),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) async {
      onDelete();
      return false;
    },
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.s16),
      decoration: BoxDecoration(
        color: colors.destructive.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        FLucideIcons.trash2,
        size: AppIconSizes.sm,
        color: colors.destructive,
      ),
    ),
    child: KnowledgeSection.item(
      onPress: onPress,
      children: [
        _LibraryTileHeader(
          title: title,
          query: query,
          leading: typeIcon != null
              ? Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: AppSpacing.s8),
                  decoration: BoxDecoration(
                    color: (typeColor ?? colors.primary)
                        .withValues(alpha: AppOpacity.subtle),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    typeIcon,
                    size: AppIconSizes.xs,
                    color: typeColor ?? colors.primary,
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (statusBadge != null) ...[
                KnowledgeStatusLabel(label: statusBadge),
                const SizedBox(width: AppSpacing.s4),
              ],
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.xs,
                color: colors.mutedForeground.withValues(alpha: AppOpacity.muted),
              ),
            ],
          ),
        ),
        ...subtitle,
      ],
    ),
  );
}

Widget _buildDecisionTile(
  BuildContext context,
  KnowledgeDecision d, {
  required String query,
  required VoidCallback onDelete,
}) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final subtitle = <Widget>[
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
        style: context.bodyCaptionStyle,
      ),
    ],
  ];
  return _buildLibraryTile(
    context,
    title: d.question,
    query: query,
    statusBadge: d.status.wire,
    typeIcon: FLucideIcons.gitBranch,
    typeColor: colors.primary,
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeDecisionDetail,
      pathParameters: {'id': d.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildNoteTile(
  BuildContext context,
  KnowledgeNote n, {
  required String query,
  required VoidCallback onDelete,
}) {
  final colors = context.theme.colors;
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    if (n.bodyMd.isNotEmpty)
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(n.bodyMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
  ];
  return _buildLibraryTile(
    context,
    title: n.title.isEmpty ? l10n.knowledgeUntitled : n.title,
    query: query,
    typeIcon: FLucideIcons.fileText,
    typeColor: colors.mutedForeground,
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'note', 'id': n.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildPrincipleTile(
  BuildContext context,
  KnowledgePrinciple p, {
  required String query,
  required VoidCallback onDelete,
}) {
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    Text(
      l10n.knowledgeDetailScope(p.scope),
      style: context.bodyCaptionStyle,
    ),
    if (p.rationaleMd.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.s4),
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(p.rationaleMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
    ],
  ];
  return _buildLibraryTile(
    context,
    title: p.statement,
    query: query,
    statusBadge: p.status.wire,
    typeIcon: FLucideIcons.badgeCheck,
    typeColor: const Color(0xFF10B981),
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'principle', 'id': p.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildAssumptionTile(
  BuildContext context,
  KnowledgeAssumption a, {
  required String query,
  required VoidCallback onDelete,
}) {
  final l10n = AppLocalizations.of(context);
  final subtitle = <Widget>[
    Text(
      l10n.knowledgeDetailConfidenceScope(
        a.confidence.toStringAsFixed(2),
        a.scope,
      ),
      style: context.bodyCaptionStyle,
    ),
  ];
  return _buildLibraryTile(
    context,
    title: a.statement,
    query: query,
    statusBadge: a.status.wire,
    typeIcon: FLucideIcons.lightbulb,
    typeColor: const Color(0xFFF59E0B),
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'assumption', 'id': a.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildConceptTile(
  BuildContext context,
  KnowledgeConcept c, {
  required String query,
  required VoidCallback onDelete,
}) {
  final subtitle = <Widget>[
    if (c.summaryMd.isNotEmpty)
      KnowledgeHighlightedText(
        text: knowledgeExcerpt(c.summaryMd),
        query: query,
        style: context.bodyCaptionStyle,
      ),
  ];
  return _buildLibraryTile(
    context,
    title: c.name,
    query: query,
    typeIcon: FLucideIcons.folderTree,
    typeColor: const Color(0xFF8B5CF6),
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'concept', 'id': c.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

Widget _buildExperimentTile(
  BuildContext context,
  KnowledgeExperiment e, {
  required String query,
  required VoidCallback onDelete,
}) {
  return _buildLibraryTile(
    context,
    title: e.hypothesis,
    query: query,
    statusBadge: e.status.wire,
    typeIcon: FLucideIcons.flaskConical,
    typeColor: const Color(0xFF06B6D4),
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'experiment', 'id': e.id},
    ),
    onDelete: onDelete,
  );
}

Widget _buildRoutineTile(
  BuildContext context,
  KnowledgeRoutine r, {
  required String query,
  required VoidCallback onDelete,
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
  final subtitle = <Widget>[
    Text(
      l10n.knowledgeRoutineLibraryMeta(dueLabel, r.intervalDays, r.scope),
      style: typography.sm.copyWith(color: dueColor),
    ),
  ];
  return _buildLibraryTile(
    context,
    title: r.statement,
    query: query,
    statusBadge: r.status.wire,
    typeIcon: FLucideIcons.calendarClock,
    typeColor: const Color(0xFFF97316),
    onPress: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'routine', 'id': r.id},
    ),
    onDelete: onDelete,
    subtitle: subtitle,
  );
}

class _LibraryTileHeader extends StatelessWidget {
  const _LibraryTileHeader({
    required this.title,
    required this.query,
    required this.trailing,
    this.leading,
  });

  final String title;
  final String query;
  final Widget trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ?leading,
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
