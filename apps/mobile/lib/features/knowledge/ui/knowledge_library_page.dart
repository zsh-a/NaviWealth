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

import '../../../core/auth/current_user.dart';
import '../../../core/shell/master_detail_layout.dart';
import '../../../core/shell/selection_query.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
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
import 'knowledge_decision_detail_page.dart';
import 'knowledge_object_detail_page.dart';
import 'knowledge_status_labels.dart';

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

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage> {
  _LibrarySegment _segment = _LibrarySegment.all;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final List<String> _searchHistory = <String>[];
  late String _searchHistoryOwner;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchHistoryOwner = ref.read(activeUserIdProvider) ?? kLocalOnlyUserId;
    _loadSearchHistory();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final next = _searchCtrl.text;
    if (next.isEmpty) {
      if (_searchQuery.isNotEmpty && mounted) {
        setState(() => _searchQuery = '');
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || next == _searchQuery) return;
      setState(() => _searchQuery = next);
    });
  }

  void _loadSearchHistory() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored =
        prefs.getStringList(
          _knowledgeLibrarySearchHistoryPrefsKey(_searchHistoryOwner),
        ) ??
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
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      _searchHistory
        ..clear()
        ..addAll(_normalizedSearchHistory(<String>[query, ..._searchHistory]));
    });
    unawaited(_persistSearchHistory());
  }

  Future<void> _persistSearchHistory() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(
      _knowledgeLibrarySearchHistoryPrefsKey(_searchHistoryOwner),
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
    final owner = ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId;
    if (owner != _searchHistoryOwner) {
      _searchHistoryOwner = owner;
      _loadSearchHistory();
    }
    final l10n = AppLocalizations.of(context);
    final library = _KnowledgeMasterDetailScope(
      enabled: false,
      child: AppAtmosphere(
        child: AdaptiveContentFrame(
          maxWidth: Breakpoints.readingColumn,
          expandSinglePrimary: true,
          padding: shellTabContentPadding(context, top: AppSpacing.s8),
          primary: _buildLibraryContent(l10n),
        ),
      ),
    );
    // Blueprint §8.2: creation lives in the page header; FAB retired.
    return ShellTabScaffold(
      title: l10n.knowledgeLibraryTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: _segment == _LibrarySegment.all
              ? l10n.knowledgeNewChooserTitle
              : _createLabel(l10n, _segment),
          onPress: () => _segment == _LibrarySegment.all
              ? _openCreateSheet(context, ref)
              : _createForSegment(context, ref, _segment),
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
              return library;
            }
            return MasterDetailLayout(
              master: _KnowledgeMasterDetailScope(
                enabled: true,
                child: AppAtmosphere(
                  child: AdaptiveContentFrame(
                    maxWidth: Breakpoints.readingColumn,
                    expandSinglePrimary: true,
                    padding: shellTabContentPadding(
                      context,
                      top: AppSpacing.s8,
                    ),
                    primary: _buildLibraryContent(l10n),
                  ),
                ),
              ),
              detail: _knowledgeLibraryDetail(
                context,
                selectedQueryOf(context),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLibraryContent(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: _onSearchKey,
                child: FTextField(
                  control: FTextFieldControl.managed(controller: _searchCtrl),
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  prefixBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: AppSpacing.s12,
                      end: AppSpacing.s8,
                    ),
                    child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
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
        _LibraryTabBar(
          selected: _segment,
          onChanged: (segment) => setState(() => _segment = segment),
        ),
        const SizedBox(height: AppSpacing.s12),
        Expanded(
          child: _LibraryList(
            segment: _segment,
            segmentLabel: _segmentLabel(l10n, _segment),
            createLabel: _createLabel(l10n, _segment),
            onCreate: () => _segment == _LibrarySegment.all
                ? _openCreateSheet(context, ref)
                : _createForSegment(context, ref, _segment),
            onSegmentChanged: (segment) => setState(() => _segment = segment),
            query: _searchQuery,
            searchHistory: _searchHistory,
            onSearchSelected: _applySearch,
            onSearchHistoryClear: _clearSearchHistory,
            onSearchHistoryItemDelete: _removeSearchHistoryItem,
            onRefresh: () => _refreshKnowledgeRepository(ref),
          ),
        ),
      ],
    );
  }
}

class _KnowledgeMasterDetailScope extends InheritedWidget {
  const _KnowledgeMasterDetailScope({
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_KnowledgeMasterDetailScope>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(_KnowledgeMasterDetailScope oldWidget) =>
      enabled != oldWidget.enabled;
}

Widget _knowledgeLibraryDetail(BuildContext context, String? selected) {
  final separator = selected?.indexOf(':') ?? -1;
  if (selected == null || separator <= 0 || separator == selected.length - 1) {
    return MasterDetailEmpty(
      message: AppLocalizations.of(context).knowledgeLibrarySelectItem,
      icon: FLucideIcons.library,
    );
  }
  final kind = selected.substring(0, separator);
  final id = selected.substring(separator + 1);
  return kind == 'decision'
      ? KnowledgeDecisionDetailPage(decisionId: id)
      : KnowledgeObjectDetailPage(kind: kind, id: id);
}

void _openKnowledgeLibraryDetail(
  BuildContext context, {
  required String kind,
  required String id,
}) {
  if (_KnowledgeMasterDetailScope.of(context)) {
    replaceSelectedQuery(
      context,
      path: KnowledgeRoutes.library,
      selected: '$kind:$id',
    );
    return;
  }
  if (kind == 'decision') {
    context.pushNamed(
      KnowledgeRouteNames.decisionDetail,
      pathParameters: {'id': id},
    );
    return;
  }
  context.pushNamed(
    KnowledgeRouteNames.objectDetail,
    pathParameters: {'kind': kind, 'id': id},
  );
}

/// Icon-only FAB that opens the knowledge type picker sheet.
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
      showKnowledgeCaptureSheet(context);
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

Future<void> _openCreateSheet(
  BuildContext context,
  WidgetRef ref, {
  _LibrarySegment activeSegment = _LibrarySegment.all,
}) async {
  final l10n = AppLocalizations.of(context);
  final activeLabel = activeSegment == _LibrarySegment.all
      ? null
      : _segmentLabel(l10n, activeSegment);
  final options = [
    KnowledgeCreateOption(
      icon: FLucideIcons.fileText,
      label: l10n.knowledgeNewNote,
      onSelected: () => showKnowledgeCaptureSheet(context),
    ),
    KnowledgeCreateOption(
      icon: FLucideIcons.gitBranch,
      label: l10n.knowledgeNewDecision,
      onSelected: () => showNewDecisionSheet(context, ref),
    ),
    KnowledgeCreateOption(
      icon: FLucideIcons.lightbulb,
      label: l10n.knowledgeNewAssumption,
      onSelected: () => showNewAssumptionSheet(context, ref),
    ),
  ];
  await showKnowledgeCreateSheet(
    context,
    options: options,
    activeLabel: activeLabel,
  );
}
