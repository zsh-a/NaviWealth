import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_capture_sheet.dart';
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
        child: Column(
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
                    )
                  : _LibrarySearchResults(value: searchResults),
            ),
          ],
        ),
      ),
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

class _LibraryBrowse extends StatelessWidget {
  const _LibraryBrowse({
    required this.scope,
    required this.selectedTag,
    required this.notes,
    required this.decisions,
  });

  final _LibraryScope scope;
  final String? selectedTag;
  final AsyncValue<List<KnowledgeNote>> notes;
  final AsyncValue<List<KnowledgeDecision>> decisions;

  @override
  Widget build(BuildContext context) {
    if (scope == _LibraryScope.notes) {
      return notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _LibraryError(),
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
        ),
      );
    }
    if (scope == _LibraryScope.decisions) {
      return decisions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _LibraryError(),
        data: (items) => _LibraryList(
          entries: items
              .map(_LibraryEntry.fromDecision)
              .toList(growable: false),
          emptyTitle: AppLocalizations.of(context)
              .knowledgeLibraryEmptyDecisionsTitle,
        ),
      );
    }
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _LibraryError(),
      data: (noteItems) => decisions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _LibraryError(),
        data: (decisionItems) {
          final entries = <_LibraryEntry>[
            ...noteItems.map(_LibraryEntry.fromNote),
            ...decisionItems.map(_LibraryEntry.fromDecision),
          ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return _LibraryList(
            entries: entries,
            emptyTitle: AppLocalizations.of(context).knowledgeLibraryEmptyTitle,
          );
        },
      ),
    );
  }
}

class _LibrarySearchResults extends StatelessWidget {
  const _LibrarySearchResults({required this.value});

  final AsyncValue<List<KnowledgeSearchHit>> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _LibraryError(),
      data: (hits) => _LibraryList(
        entries: hits
            .map((hit) => _LibraryEntry.fromSearchHit(hit))
            .toList(growable: false),
        emptyTitle: AppLocalizations.of(context).knowledgeLibraryNoResultsTitle,
        emptyMessage: AppLocalizations.of(context)
            .knowledgeLibraryNoResultsBody,
        emptyIcon: FLucideIcons.searchX,
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.entries,
    required this.emptyTitle,
    this.emptyMessage,
    this.emptyIcon = FLucideIcons.library,
  });

  final List<_LibraryEntry> entries;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        compact: true,
      );
    }
    final l10n = AppLocalizations.of(context);
    return ListView.separated(
      padding: shellTabContentPadding(context),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return KnowledgeEntryTile(
          key: ValueKey<String>('knowledge-library-${entry.kind}-${entry.id}'),
          title: entry.title.isEmpty ? l10n.knowledgeUntitled : entry.title,
          subtitle: entry.subtitle,
          meta: entry.meta,
          tags: entry.tags,
          kindLabel: entry.kind == 'note'
              ? l10n.knowledgeKindNote
              : l10n.knowledgeKindDecision,
          icon: entry.kind == 'note'
              ? FLucideIcons.fileText
              : FLucideIcons.circleCheck,
          onPress: () => context.push(
            entry.kind == 'note'
                ? KnowledgeRoutes.note(entry.id)
                : KnowledgeRoutes.decision(entry.id),
          ),
        );
      },
    );
  }
}

class _LibraryError extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppEmptyState.error(
    title: AppLocalizations.of(context).commonLoadFailed,
    compact: true,
  );
}

class _LibraryEntry {
  const _LibraryEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.tags,
    required this.updatedAt,
  });

  final String kind;
  final String id;
  final String title;
  final String subtitle;
  final String meta;
  final List<String> tags;
  final DateTime updatedAt;

  factory _LibraryEntry.fromNote(KnowledgeNote note) => _LibraryEntry(
    kind: 'note',
    id: note.id,
    title: note.title,
    subtitle: note.bodyMd,
    meta: '',
    tags: note.tags,
    updatedAt: note.sync.updatedAt,
  );

  factory _LibraryEntry.fromDecision(KnowledgeDecision decision) =>
      _LibraryEntry(
        kind: 'decision',
        id: decision.id,
        title: decision.question,
        subtitle: decision.selectedLabel,
        meta: '',
        tags: const <String>[],
        updatedAt: decision.sync.updatedAt,
      );

  factory _LibraryEntry.fromSearchHit(KnowledgeSearchHit hit) => _LibraryEntry(
    kind: hit.kind,
    id: hit.id,
    title: hit.title,
    subtitle: hit.excerpt,
    meta: '',
    tags: hit.document.note?.tags ?? const <String>[],
    updatedAt: hit.document.updatedAt,
  );
}
