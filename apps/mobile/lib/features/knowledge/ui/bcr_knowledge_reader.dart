import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bcr_knowledge_providers.dart';
import '../data/bcr_knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/bcr_knowledge_source.dart';
import 'bcr_knowledge_sync_feedback.dart';
import 'knowledge_capture_sheet.dart';
import 'widgets/knowledge_source_link.dart';

Future<BcrKnowledgeReference?> showBcrKnowledgeReader({
  required BuildContext context,
  required BcrKnowledgeHit hit,
  bool picking = false,
  String query = '',
}) => Navigator.of(context).push<BcrKnowledgeReference>(
  MaterialPageRoute(
    builder: (_) =>
        BcrKnowledgeReader(hit: hit, picking: picking, query: query),
  ),
);

class BcrKnowledgeReader extends ConsumerStatefulWidget {
  const BcrKnowledgeReader({
    super.key,
    required this.hit,
    this.picking = false,
    this.query = '',
  });
  final BcrKnowledgeHit hit;
  final bool picking;
  final String query;

  @override
  ConsumerState<BcrKnowledgeReader> createState() => _BcrKnowledgeReaderState();
}

class _BcrKnowledgeReaderState extends ConsumerState<BcrKnowledgeReader> {
  final _offsets = <int>[0];
  bool _busy = false;
  String? _error;

  Future<void> _cite() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final owner = await ref.read(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.read(bcrKnowledgeRepositoryProvider.future);
      final current = await repository.findSource(owner, widget.hit.source.id);
      if (current?.cacheRevision != widget.hit.source.cacheRevision) {
        throw BcrKnowledgeCacheFailure.changed;
      }
      final currentOwner = await ref.read(knowledgeOwnerUserIdProvider.future);
      if (!mounted || currentOwner != owner) {
        return;
      }
      final reference = BcrKnowledgeReference.fromHit(
        widget.hit,
        query: widget.query,
      );
      if (!mounted) return;
      if (widget.picking) {
        Navigator.of(context).pop(reference);
      } else {
        await showKnowledgeDecisionCapturePage(
          context,
          initialRationale: reference.toMarkdown(),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = bcrKnowledgeFailureMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hit = widget.hit;
    // Keep this open reader owner-scoped even if the active identity changes.
    final sources = ref.watch(bcrKnowledgeSourcesProvider);
    final live =
        !sources.isLoading &&
        sources.value?.any(
              (source) =>
                  source.id == hit.source.id &&
                  source.cacheRevision == hit.source.cacheRevision,
            ) ==
            true;
    final body = hit.note.body;
    final page = bcrTextPage(body, _offsets.last);
    return AppPageScaffold(
      title: live ? hit.note.title : l10n.knowledgeBcrTitle,
      child: live
          ? ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                Text(hit.source.label, style: context.captionLabelStyle),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  l10n.knowledgeBcrTextOnly,
                  style: context.bodyCaptionStyle,
                ),
                if (hit.source.noteUrl(hit.note.id) case final url?) ...[
                  const SizedBox(height: AppSpacing.s12),
                  KnowledgeSourceLink(sourceUrl: url.toString()),
                ],
                const SizedBox(height: AppSpacing.s16),
                AiMarkdown(key: ValueKey(page.offset), text: page.text),
                const SizedBox(height: AppSpacing.s16),
                if (_offsets.length > 1)
                  AppQuietButton(
                    label: l10n.routeGoBack,
                    onPress: () => setState(() => _offsets.removeLast()),
                  ),
                if (page.nextOffset != null)
                  AppQuietButton(
                    label: l10n.knowledgeBcrReadMore,
                    onPress: () =>
                        setState(() => _offsets.add(page.nextOffset!)),
                  ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  l10n.knowledgeBcrFingerprint,
                  style: context.captionLabelStyle,
                ),
                SelectableText(
                  hit.note.fingerprint,
                  style: context.captionStyle,
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  l10n.knowledgeBcrEvidenceHint,
                  style: context.bodyCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  BcrKnowledgeReference.fromHit(
                    hit,
                    query: widget.query,
                  ).excerpt,
                  style: context.bodyCaptionStyle,
                ),
                const SizedBox(height: AppSpacing.s12),
                AppBusyButton(
                  buttonKey: const Key('bcr-cite-note'),
                  label: widget.picking
                      ? l10n.knowledgeBcrInsert
                      : l10n.knowledgeNewDecision,
                  busy: _busy,
                  onPress: _cite,
                ),
                if (_error case final message?) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppStatusBanner(message: message, kind: AppStatusKind.error),
                ],
              ],
            )
          : sources.isLoading
          ? kDefaultLoading
          : Center(child: Text(l10n.knowledgeBcrChanged)),
    );
  }
}
