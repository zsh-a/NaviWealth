/// KnowledgeOS Library tab (`docs/domains/knowledgeos-domain.md` §5).
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

import '../../../core/shell/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '../domain/knowledge_search_suggestions.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

part 'knowledge_library_actions.dart';
part 'knowledge_library_controls.dart';
part 'knowledge_library_list.dart';
part 'knowledge_library_model.dart';
part 'knowledge_library_segment_list.dart';
part 'knowledge_library_tiles.dart';

class KnowledgeLibraryPage extends ConsumerStatefulWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  ConsumerState<KnowledgeLibraryPage> createState() =>
      _KnowledgeLibraryPageState();
}

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage>
    with KnowledgeFabScrollHideMixin {
  _LibrarySegment _segment = _LibrarySegment.all;
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
                padding: shellTabContentPadding(context, top: AppSpacing.s8),
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
                              hint: l10n.knowledgeLibrarySearchSegmentHint(
                                _segmentLabel(l10n, _segment),
                              ),
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
            bottom: shellTabFloatingActionBottom(context),
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
    final l10n = AppLocalizations.of(context);
    return AppFloatingActionSurface(
      icon: FLucideIcons.plus,
      tooltip: activeSegment == _LibrarySegment.all
          ? l10n.knowledgeNewChooserTitle
          : _createLabel(l10n, activeSegment),
      onPress: () => activeSegment == _LibrarySegment.all
          ? _openCreateSheet(context, ref)
          : _createForSegment(context, ref, activeSegment),
    );
  }

  void _createForSegment(
    BuildContext context,
    WidgetRef ref,
    _LibrarySegment segment,
  ) {
    switch (segment) {
      case _LibrarySegment.all:
        _openCreateSheet(context, ref);
      case _LibrarySegment.decisions:
        showNewDecisionSheet(context, ref);
      case _LibrarySegment.principles:
        showNewPrincipleSheet(context, ref);
      case _LibrarySegment.assumptions:
        showNewAssumptionSheet(context, ref);
      case _LibrarySegment.notes:
        showKnowledgeCaptureSheet(context, ref);
      case _LibrarySegment.concepts:
        showNewConceptSheet(context, ref);
      case _LibrarySegment.experiments:
        showNewExperimentSheet(context, ref);
      case _LibrarySegment.routines:
        showNewRoutineSheet(context, ref);
    }
  }

  String _createLabel(AppLocalizations l10n, _LibrarySegment segment) =>
      switch (segment) {
        _LibrarySegment.all => l10n.knowledgeNewChooserTitle,
        _LibrarySegment.decisions => l10n.knowledgeNewDecision,
        _LibrarySegment.principles => l10n.knowledgeNewPrinciple,
        _LibrarySegment.assumptions => l10n.knowledgeNewAssumption,
        _LibrarySegment.notes => l10n.knowledgeNewNote,
        _LibrarySegment.concepts => l10n.knowledgeNewConcept,
        _LibrarySegment.experiments => l10n.knowledgeNewExperiment,
        _LibrarySegment.routines => l10n.knowledgeNewRoutine,
      };

  Future<void> _openCreateSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final activeLabel = activeSegment == _LibrarySegment.all
        ? null
        : _segmentLabel(l10n, activeSegment);
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
