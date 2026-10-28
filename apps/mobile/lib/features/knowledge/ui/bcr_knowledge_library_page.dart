import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bcr_knowledge_providers.dart';
import '../data/bcr_knowledge_sync_service.dart';
import '../data/providers.dart';
import '../domain/bcr_knowledge_connection.dart';
import '../domain/bcr_knowledge_source.dart';
import '../domain/knowledge_text.dart';
import 'bcr_knowledge_reader.dart';
import 'bcr_knowledge_sync_feedback.dart';
import 'bcr_knowledge_sync_sheet.dart';

Future<BcrKnowledgeReference?> pickBcrKnowledgeReference(
  BuildContext context,
) => Navigator.of(context).push<BcrKnowledgeReference>(
  MaterialPageRoute(
    builder: (_) => const BcrKnowledgeLibraryPage(picking: true),
  ),
);

class BcrKnowledgeLibraryPage extends ConsumerStatefulWidget {
  const BcrKnowledgeLibraryPage({super.key, this.picking = false});
  final bool picking;

  @override
  ConsumerState<BcrKnowledgeLibraryPage> createState() =>
      _BcrKnowledgeLibraryPageState();
}

class _BcrKnowledgeLibraryPageState
    extends ConsumerState<BcrKnowledgeLibraryPage> {
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _remove(BcrKnowledgeSource source) async {
    final l10n = AppLocalizations.of(context);
    if (await showConfirmDialog(
              context: context,
              title: Text(l10n.knowledgeBcrRemove),
              body: Text(l10n.knowledgeBcrRemoveBody),
              confirmLabel: l10n.commonDelete,
              cancelLabel: l10n.commonCancel,
              destructive: true,
            ) !=
            true ||
        !mounted) {
      return;
    }
    try {
      final owner = await ref.read(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.read(bcrKnowledgeRepositoryProvider.future);
      await repository.removeSource(
        owner: owner,
        id: source.id,
        expectedCacheRevision: source.cacheRevision,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = bcrKnowledgeFailureMessage(context, error));
      }
    }
  }

  Future<void> _open(BcrKnowledgeHit hit) async {
    final reference = await showBcrKnowledgeReader(
      context: context,
      hit: hit,
      picking: widget.picking,
      query: _query,
    );
    if (mounted && widget.picking && reference != null) {
      Navigator.of(context).pop(reference);
    }
  }

  Future<void> _sync(BcrKnowledgeConnection connection) async {
    try {
      final service = await ref.read(bcrKnowledgeSyncServiceProvider.future);
      await service.sync(connection, manual: true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = bcrKnowledgeFailureMessage(context, error));
      }
    }
  }

  Future<void> _disconnect(BcrKnowledgeConnection connection) async {
    final l10n = AppLocalizations.of(context);
    if (await showConfirmDialog(
              context: context,
              title: Text(l10n.knowledgeBcrRemove),
              body: Text(l10n.knowledgeBcrRemoveBody),
              confirmLabel: l10n.knowledgeBcrRemove,
              cancelLabel: l10n.commonCancel,
              destructive: true,
            ) !=
            true ||
        !mounted) {
      return;
    }
    try {
      final service = await ref.read(bcrKnowledgeSyncServiceProvider.future);
      await service.disconnect(connection);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = bcrKnowledgeFailureMessage(context, error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(bcrKnowledgeSourcesProvider);
    final connectionsAsync = ref.watch(bcrKnowledgeConnectionsProvider);
    final connections =
        connectionsAsync.value ?? const <BcrKnowledgeConnection>[];
    final statuses =
        ref.watch(bcrKnowledgeSyncStatusProvider).value ??
        const <String, BcrSyncStatus>{};
    return AppPageScaffold(
      title: widget.picking ? l10n.knowledgeBcrCite : l10n.knowledgeBcrTitle,
      actions: [
        AppIconButton(
          icon: FLucideIcons.plus,
          tooltip: l10n.knowledgeBcrAdd,
          onPress: () => showBcrKnowledgeSyncSheet(context),
        ),
      ],
      child: value.when(
        loading: () => kDefaultLoading,
        error: (error, stack) => kDefaultError(
          context,
          error,
          stack,
          onRetry: () => ref.invalidate(bcrKnowledgeSourcesProvider),
        ),
        data: (sources) {
          final hits = searchBcrKnowledge(sources, _query);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: AppSearchField(
                  controller: _search,
                  hint: l10n.knowledgeBcrSearch,
                  clearLabel: l10n.aiChatSessionsSearchClear,
                  onChanged: (query) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), () {
                      if (mounted) setState(() => _query = query);
                    });
                  },
                ),
              ),
              if (_error case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16,
                  ),
                  child: AppStatusBanner(
                    message: message,
                    kind: AppStatusKind.error,
                  ),
                ),
              Expanded(
                child: sources.isEmpty && connections.isEmpty
                    ? AppEmptyState(
                        icon: FLucideIcons.bookOpen,
                        title: l10n.knowledgeBcrEmpty,
                        message: l10n.knowledgeBcrHint,
                        action: AppActionButton(
                          onPress: () => showBcrKnowledgeSyncSheet(context),
                          child: Text(l10n.knowledgeBcrAdd),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s16,
                          0,
                          AppSpacing.s16,
                          AppSpacing.s16,
                        ),
                        children: [
                          if (_query.trim().isEmpty) ...[
                            for (final connection in connections)
                              _connectionSection(
                                context,
                                connection,
                                sources
                                    .where(
                                      (source) => source.id == connection.id,
                                    )
                                    .firstOrNull,
                                statuses[connection.id],
                              ),
                            for (final source in sources)
                              if (!connections.any(
                                (connection) => connection.id == source.id,
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.s12,
                                  ),
                                  child: AppSection.item(
                                    title: source.label,
                                    children: [
                                      Text(
                                        l10n.knowledgeBcrNoteCount(
                                          source.notes.length,
                                        ),
                                        style: context.bodyCaptionStyle,
                                      ),
                                      Text(
                                        '${l10n.knowledgeBcrCachedAt}: ${MaterialLocalizations.of(context).formatMediumDate(source.importedAt.toLocal())}',
                                        style: context.captionStyle,
                                      ),
                                      Wrap(
                                        spacing: AppSpacing.s12,
                                        children: [
                                          AppQuietButton(
                                            label: l10n.knowledgeBcrAdd,
                                            onPress: () =>
                                                showBcrKnowledgeSyncSheet(
                                                  context,
                                                  source: source,
                                                ),
                                          ),
                                          AppQuietButton(
                                            label: l10n.commonDelete,
                                            tone: AppQuietButtonTone.danger,
                                            onPress: () => _remove(source),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                          if (hits.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Text(
                                l10n.knowledgeBcrNoResults,
                                style: context.bodyCaptionStyle,
                              ),
                            ),
                          for (final hit in hits)
                            AppNavRow(
                              key: ValueKey(
                                'bcr-note-${hit.source.id}-${hit.note.id}',
                              ),
                              icon: FLucideIcons.fileText,
                              title: hit.note.title,
                              subtitle:
                                  '${hit.source.label} · ${knowledgeSearchExcerpt(hit.note.body, _query)}',
                              titleMaxLines: 1,
                              subtitleMaxLines: 2,
                              onTap: () => _open(hit),
                            ),
                          if (hits.length == 50)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.s12),
                              child: Text(
                                l10n.knowledgeBcrResultsLimit,
                                style: context.captionStyle,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _connectionSection(
    BuildContext context,
    BcrKnowledgeConnection connection,
    BcrKnowledgeSource? source,
    BcrSyncStatus? status,
  ) {
    final l10n = AppLocalizations.of(context);
    final checked = connection.checkedAt?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: AppSection.item(
        title: connection.label,
        children: [
          Text(
            '${connection.target.owner}/${connection.target.repository} · ${connection.target.branch}',
            style: context.captionStyle,
          ),
          Text(
            l10n.knowledgeBcrNoteCount(source?.notes.length ?? 0),
            style: context.bodyCaptionStyle,
          ),
          if (checked != null)
            Text(
              '${l10n.knowledgeBcrLastChecked}: ${MaterialLocalizations.of(context).formatMediumDate(checked)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(checked))}',
              style: context.captionStyle,
            ),
          if (status?.error case final error?) ...[
            const SizedBox(height: AppSpacing.s8),
            AppStatusBanner(
              message: bcrKnowledgeFailureMessage(context, error),
              kind: AppStatusKind.error,
              compact: true,
            ),
            if (status?.retryable == true)
              Text(l10n.knowledgeBcrWaitingRetry, style: context.captionStyle),
          ],
          Wrap(
            spacing: AppSpacing.s12,
            children: [
              AppQuietButton(
                key: ValueKey('bcr-sync-${connection.id}'),
                label: l10n.knowledgeBcrSyncNow,
                busyLabel: l10n.knowledgeBcrSyncing,
                busy: status?.syncing ?? false,
                onPress: status?.retryAt?.isAfter(DateTime.now()) == true
                    ? null
                    : () => _sync(connection),
              ),
              AppQuietButton(
                label: l10n.knowledgeBcrManage,
                onPress: () =>
                    showBcrKnowledgeSyncSheet(context, connection: connection),
              ),
              AppQuietButton(
                label: l10n.knowledgeBcrRemove,
                tone: AppQuietButtonTone.danger,
                onPress: () => _disconnect(connection),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
