import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../core/shell/master_detail_layout.dart';
import '../../../core/shell/selection_query.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_text.dart';
import 'knowledge_capture_sheet.dart';
import 'knowledge_decision_detail_page.dart';
import 'knowledge_note_detail_page.dart';
import 'widgets/knowledge_entry_tile.dart';

enum _LibraryScope {
  all(null),
  notes('note'),
  decisions('decision');

  const _LibraryScope(this.kind);
  final String? kind;
}

class KnowledgeLibraryPage extends ConsumerStatefulWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  ConsumerState<KnowledgeLibraryPage> createState() =>
      _KnowledgeLibraryPageState();
}

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage> {
  static const _searchDebounce = Duration(milliseconds: 250);
  static const _tagFacetLimit = 12;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  var _scope = _LibraryScope.all;
  var _query = '';
  String? _selectedTag;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _scheduleSearch(TextEditingValue value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) return;
      setState(() => _query = value.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeLibraryTitle,
      directActionBudget: 1,
      actions: <ShellHeaderActionSpec>[
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          onPress: () => showKnowledgeCaptureSheet(context),
        ),
      ],
      child: ShellTabPause(
        routePath: KnowledgeRoutes.library,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (GoRouter.maybeOf(context) == null ||
                !MasterDetailLayout.shouldUseMasterDetail(
                  constraints.maxWidth,
                )) {
              return _buildBody(context, inMasterDetail: false);
            }
            return MasterDetailLayout(
              master: _buildBody(context, inMasterDetail: true),
              detail: _libraryDetail(context, selectedQueryOf(context)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool inMasterDetail}) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(knowledgeNotesProvider);
    final decisions = ref.watch(knowledgeDecisionsProvider);
    final tagFacets = _tagFacets(
      notes.asData?.value ?? const <KnowledgeNote>[],
      selectedTag: _selectedTag,
    );
    final searchResults = _query.isEmpty
        ? null
        : ref.watch(
            knowledgeLibrarySearchProvider((
              query: _query,
              kind: _scope.kind,
              tag: _selectedTag,
            )),
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s12,
            AppSpacing.s16,
            AppSpacing.s4,
          ),
          child: Column(
            children: [
              FTextField(
                key: const Key('knowledge-library-search'),
                control: FTextFieldControl.managed(
                  controller: _searchController,
                  onChange: _scheduleSearch,
                ),
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                maxLines: 1,
                prefixBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: AppSpacing.s12,
                    end: AppSpacing.s8,
                  ),
                  child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
                ),
                hint: l10n.knowledgeLibrarySearchHint,
              ),
              const SizedBox(height: AppSpacing.s10),
              AppAdaptiveChoice<_LibraryScope>(
                title: l10n.knowledgeLibraryFilterTitle,
                options: _LibraryScope.values,
                value: _scope,
                labelOf: (scope) => switch (scope) {
                  _LibraryScope.all => l10n.knowledgeSegmentAll,
                  _LibraryScope.notes => l10n.knowledgeSegmentNotes,
                  _LibraryScope.decisions => l10n.knowledgeSegmentDecisions,
                },
                iconOf: (scope) => switch (scope) {
                  _LibraryScope.all => FLucideIcons.library,
                  _LibraryScope.notes => FLucideIcons.fileText,
                  _LibraryScope.decisions => FLucideIcons.circleCheck,
                },
                onChanged: (scope) {
                  setState(() {
                    _scope = scope;
                    if (scope == _LibraryScope.decisions) {
                      _selectedTag = null;
                    }
                  });
                },
              ),
              if (tagFacets.isNotEmpty &&
                  _scope != _LibraryScope.decisions) ...[
                const SizedBox(height: AppSpacing.s10),
                _LibraryTagFilter(
                  tags: tagFacets,
                  selectedTag: _selectedTag,
                  allLabel: l10n.knowledgeLibraryAllTags,
                  semanticLabel: l10n.knowledgeLibraryTagFilterLabel,
                  onChanged: (tag) {
                    setState(() {
                      _selectedTag = tag;
                      if (tag != null) _scope = _LibraryScope.notes;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: searchResults == null
              ? _LibraryBrowse(
                  scope: _scope,
                  selectedTag: _selectedTag,
                  notes: notes,
                  decisions: decisions,
                  inMasterDetail: inMasterDetail,
                )
              : _LibrarySearchResults(
                  value: searchResults,
                  inMasterDetail: inMasterDetail,
                  onRetry: () => ref.invalidate(
                    knowledgeLibrarySearchProvider((
                      query: _query,
                      kind: _scope.kind,
                      tag: _selectedTag,
                    )),
                  ),
                ),
        ),
      ],
    );
  }

  List<String> _tagFacets(
    List<KnowledgeNote> notes, {
    required String? selectedTag,
  }) {
    final counts = <String, int>{};
    for (final note in notes) {
      for (final tag in note.tags.toSet()) {
        if (tag.trim().isEmpty) continue;
        counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final tags = counts.keys.toList(growable: false)
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        final byLabel = a.toLowerCase().compareTo(b.toLowerCase());
        return byLabel != 0 ? byLabel : a.compareTo(b);
      });
    final visible = tags.take(_tagFacetLimit).toList();
    if (selectedTag != null && !visible.contains(selectedTag)) {
      visible.insert(0, selectedTag);
    }
    return visible;
  }
}

class _LibraryTagFilter extends StatelessWidget {
  const _LibraryTagFilter({
    required this.tags,
    required this.selectedTag,
    required this.allLabel,
    required this.semanticLabel,
    required this.onChanged,
  });

  final List<String> tags;
  final String? selectedTag;
  final String allLabel;
  final String semanticLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: AppControlHeights.touchTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tags.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s8),
          itemBuilder: (context, index) {
            final tag = index == 0 ? null : tags[index - 1];
            return AppFilterChip(
              key: ValueKey<String>(
                tag == null
                    ? 'knowledge-library-all-tags'
                    : 'knowledge-library-tag-$tag',
              ),
              label: tag ?? allLabel,
              active: selectedTag == tag,
              icon: tag == null ? FLucideIcons.tags : FLucideIcons.tag,
              onPress: () => onChanged(tag),
            );
          },
        ),
      ),
    );
  }
}

class _LibraryBrowse extends ConsumerWidget {
  const _LibraryBrowse({
    required this.scope,
    required this.selectedTag,
    required this.notes,
    required this.decisions,
    required this.inMasterDetail,
  });

  final _LibraryScope scope;
  final String? selectedTag;
  final AsyncValue<List<KnowledgeNote>> notes;
  final AsyncValue<List<KnowledgeDecision>> decisions;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget skeleton() => AppListPageSkeleton(
      showControls: false,
      padding: shellTabContentPadding(context),
    );
    if (scope == _LibraryScope.notes) {
      return notes.when(
        loading: skeleton,
        error: (_, _) => _LibraryError(
          onRetry: () => ref.invalidate(knowledgeNotesProvider),
        ),
        data: (items) => _LibraryList(
          entries: items
              .where(
                (note) =>
                    selectedTag == null || note.tags.contains(selectedTag),
              )
              .map(_LibraryEntry.fromNote)
              .toList(growable: false),
          emptyTitle: AppLocalizations.of(context)
              .knowledgeLibraryEmptyNotesTitle,
          inMasterDetail: inMasterDetail,
        ),
      );
    }
    if (scope == _LibraryScope.decisions) {
      return decisions.when(
        loading: skeleton,
        error: (_, _) => _LibraryError(
          onRetry: () => ref.invalidate(knowledgeDecisionsProvider),
        ),
        data: (items) => _LibraryList(
          entries: items
              .map(_LibraryEntry.fromDecision)
              .toList(growable: false),
          emptyTitle: AppLocalizations.of(context)
              .knowledgeLibraryEmptyDecisionsTitle,
          inMasterDetail: inMasterDetail,
        ),
      );
    }
    void retryAll() {
      ref.invalidate(knowledgeNotesProvider);
      ref.invalidate(knowledgeDecisionsProvider);
    }

    return notes.when(
      loading: skeleton,
      error: (_, _) => _LibraryError(onRetry: retryAll),
      data: (noteItems) => decisions.when(
        loading: skeleton,
        error: (_, _) => _LibraryError(onRetry: retryAll),
        data: (decisionItems) {
          final entries = <_LibraryEntry>[
            ...noteItems.map(_LibraryEntry.fromNote),
            ...decisionItems.map(_LibraryEntry.fromDecision),
          ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return _LibraryList(
            entries: entries,
            emptyTitle: AppLocalizations.of(context).knowledgeLibraryEmptyTitle,
            groupByDate: selectedTag == null,
            inMasterDetail: inMasterDetail,
          );
        },
      ),
    );
  }
}

class _LibrarySearchResults extends StatelessWidget {
  const _LibrarySearchResults({
    required this.value,
    required this.inMasterDetail,
    required this.onRetry,
  });

  final AsyncValue<List<KnowledgeSearchHit>> value;
  final bool inMasterDetail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => AppListPageSkeleton(
        showControls: false,
        padding: shellTabContentPadding(context),
      ),
      error: (_, _) => _LibraryError(onRetry: onRetry),
      data: (hits) => _LibraryList(
        entries: hits
            .map((hit) => _LibraryEntry.fromSearchHit(hit))
            .toList(growable: false),
        emptyTitle: AppLocalizations.of(context).knowledgeLibraryNoResultsTitle,
        emptyMessage: AppLocalizations.of(context)
            .knowledgeLibraryNoResultsBody,
        emptyIcon: FLucideIcons.searchX,
        inMasterDetail: inMasterDetail,
      ),
    );
  }
}

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.entries,
    required this.emptyTitle,
    required this.inMasterDetail,
    this.emptyMessage,
    this.emptyIcon = FLucideIcons.library,
    this.groupByDate = false,
  });

  final List<_LibraryEntry> entries;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final bool inMasterDetail;

  /// Groups rows into 今天/昨天/本周/更早 sections (the activity-feed date
  /// labels) — used by the default merged browse view only.
  final bool groupByDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        compact: true,
      );
    }
    final l10n = AppLocalizations.of(context);
    if (groupByDate) {
      return _buildGrouped(context, ref, l10n);
    }
    return ListView.separated(
      padding: shellTabContentPadding(context),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s10),
      itemBuilder: (context, index) =>
          _buildEntryTile(context, ref, l10n, entries[index]),
    );
  }

  Widget _buildGrouped(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final sections = _groupByUpdatedBucket(entries, l10n);
    return ListView(
      padding: shellTabContentPadding(context),
      children: [
        for (final (label, sectionEntries) in sections) ...[
          SectionHeader(
            title: label,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s8,
              AppSpacing.s4,
              AppSpacing.s8,
            ),
          ),
          for (var index = 0; index < sectionEntries.length; index++) ...[
            _buildEntryTile(context, ref, l10n, sectionEntries[index]),
            if (index != sectionEntries.length - 1)
              const SizedBox(height: AppSpacing.s10),
          ],
          const SizedBox(height: AppSpacing.s10),
        ],
      ],
    );
  }

  Widget _buildEntryTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    _LibraryEntry entry,
  ) {
    final colors = context.theme.colors;
    return KnowledgeEntryTile(
      key: ValueKey<String>('knowledge-library-${entry.kind}-${entry.id}'),
      title: entry.title.isEmpty ? l10n.knowledgeUntitled : entry.title,
      subtitle: entry.subtitle,
      meta: _relativeMeta(l10n, entry.updatedAt),
      tags: entry.tags,
      kindLabel: entry.kind == 'note'
          ? l10n.knowledgeKindNote
          : l10n.knowledgeKindDecision,
      icon: entry.kind == 'note'
          ? FLucideIcons.fileText
          : FLucideIcons.circleCheck,
      iconColor: entry.kind == 'note'
          ? colors.primary
          : context.appTheme.status.info.fg,
      decisionStatus: entry.decisionStatus,
      menuActions: [
        AppAdaptiveAction(
          icon: FLucideIcons.trash2,
          title: l10n.commonDelete,
          destructive: true,
          onPress: () => _deleteEntry(context, ref, entry),
        ),
      ],
      onPress: () =>
          _openEntry(context, entry: entry, inMasterDetail: inMasterDetail),
    );
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    _LibraryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context);
    final isNote = entry.kind == 'note';
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(
        isNote
            ? l10n.knowledgeNoteDeleteConfirmTitle
            : l10n.knowledgeDecisionDeleteConfirmTitle,
      ),
      body: Text(l10n.knowledgeDeleteConfirmBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final service = await ref.read(knowledgeDeletionServiceProvider.future);
      await service.delete(
        kind: isNote ? KnowledgeEntryKind.note : KnowledgeEntryKind.decision,
        id: entry.id,
      );
      ref.invalidate(knowledgeNotesProvider);
      ref.invalidate(knowledgeDecisionsProvider);
      if (!context.mounted) return;
      // Clear the side pane if the deleted entry was open there.
      if (inMasterDetail &&
          selectedQueryOf(context) == '${entry.kind}:${entry.id}') {
        replaceSelectedQuery(
          context,
          path: KnowledgeRoutes.library,
          selected: null,
        );
      }
      AppMessenger.show(context, ToastKind.success, l10n.commonDeleted);
    } on Object catch (error, stackTrace) {
      if (!context.mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'delete knowledge entry',
        ),
      );
    }
  }
}

/// Relative "n minutes/hours/days ago" row meta, with a short locale date
/// fallback — the same convention the health/chat surfaces use via
/// [AppFormatters.relativeTime].
String _relativeMeta(AppLocalizations l10n, DateTime updatedAt) {
  return AppFormatters.relativeTime(
    updatedAt,
    justNow: l10n.aiChatRelativeJustNow,
    minutesAgo: l10n.aiChatRelativeMinutesAgo,
    hoursAgo: l10n.aiChatRelativeHoursAgo,
    daysAgo: l10n.aiChatRelativeDaysAgo,
    dateFallback: (day) {
      final local = day.toLocal();
      final mm = local.month.toString().padLeft(2, '0');
      final dd = local.day.toString().padLeft(2, '0');
      return '$mm-$dd';
    },
  );
}

/// Buckets entries (already sorted newest-first) into the activity-feed
/// date sections: today / yesterday / this week / earlier.
List<(String, List<_LibraryEntry>)> _groupByUpdatedBucket(
  List<_LibraryEntry> entries,
  AppLocalizations l10n,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 6));
  String labelFor(DateTime at) {
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return l10n.activityFeedToday;
    if (day == yesterday) return l10n.activityFeedYesterday;
    if (!day.isBefore(weekStart)) return l10n.activityFeedThisWeek;
    return l10n.activityFeedEarlier;
  }

  final sections = <String, List<_LibraryEntry>>{};
  for (final entry in entries) {
    sections
        .putIfAbsent(labelFor(entry.updatedAt.toLocal()), () => [])
        .add(entry);
  }
  return sections.entries.map((e) => (e.key, e.value)).toList(growable: false);
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState.error(
      title: l10n.commonLoadFailed,
      retryLabel: l10n.commonRetry,
      onRetry: onRetry,
      compact: true,
    );
  }
}

/// Builds the right-hand detail pane for the desktop master-detail layout.
///
/// The `?selected=` value carries the entry kind as a prefix
/// (`note:<id>` / `decision:<id>`) because the library mixes both kinds in
/// one list — unlike the single-kind master-detail surfaces elsewhere.
Widget _libraryDetail(BuildContext context, String? selected) {
  final l10n = AppLocalizations.of(context);
  Widget empty() => MasterDetailEmpty(
    message: l10n.activitySelectEntry,
    icon: FLucideIcons.library,
  );
  if (selected == null || selected.isEmpty) return empty();
  final separator = selected.indexOf(':');
  if (separator <= 0 || separator == selected.length - 1) return empty();
  final id = selected.substring(separator + 1);
  return switch (selected.substring(0, separator)) {
    'note' => KnowledgeNoteDetailPage(noteId: id),
    'decision' => KnowledgeDecisionDetailPage(decisionId: id),
    _ => empty(),
  };
}

void _openEntry(
  BuildContext context, {
  required _LibraryEntry entry,
  required bool inMasterDetail,
}) {
  if (inMasterDetail) {
    replaceSelectedQuery(
      context,
      path: KnowledgeRoutes.library,
      selected: '${entry.kind}:${entry.id}',
    );
    return;
  }
  context.push(
    entry.kind == 'note'
        ? KnowledgeRoutes.note(entry.id)
        : KnowledgeRoutes.decision(entry.id),
  );
}

class _LibraryEntry {
  const _LibraryEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.updatedAt,
    this.decisionStatus,
  });

  final String kind;
  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final DateTime updatedAt;
  final DecisionStatus? decisionStatus;

  factory _LibraryEntry.fromNote(KnowledgeNote note) => _LibraryEntry(
    kind: 'note',
    id: note.id,
    title: note.title,
    subtitle: knowledgeExcerpt(note.bodyMd),
    tags: note.tags,
    updatedAt: note.sync.updatedAt,
  );

  factory _LibraryEntry.fromDecision(KnowledgeDecision decision) =>
      _LibraryEntry(
        kind: 'decision',
        id: decision.id,
        title: decision.question,
        subtitle: decision.selectedLabel,
        tags: const <String>[],
        updatedAt: decision.sync.updatedAt,
        decisionStatus: decision.status,
      );

  factory _LibraryEntry.fromSearchHit(KnowledgeSearchHit hit) => _LibraryEntry(
    kind: hit.kind,
    id: hit.id,
    title: hit.title,
    subtitle: hit.excerpt,
    tags: hit.document.note?.tags ?? const <String>[],
    updatedAt: hit.document.updatedAt,
    decisionStatus: hit.document.decision?.status,
  );
}
