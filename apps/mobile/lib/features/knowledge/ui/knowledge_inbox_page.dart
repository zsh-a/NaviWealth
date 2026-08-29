import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_capture_sheet.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeInboxTitle,
      directActionBudget: 1,
      actions: <ShellHeaderActionSpec>[
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.knowledgeCaptureAction,
          onPress: () => showKnowledgeCaptureSheet(context),
        ),
      ],
      child: ShellTabPause(
        routePath: KnowledgeRoutes.inbox,
        child: _NotesList(notes: ref.watch(knowledgeNotesProvider)),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes});

  final AsyncValue<List<KnowledgeNote>> notes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(l10n.commonLoadFailed)),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FLucideIcons.notebookPen,
                    size: AppIconSizes.xl,
                    color: context.theme.colors.mutedForeground,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Text(l10n.knowledgeInboxEmptyTitle),
                  const SizedBox(height: AppSpacing.s12),
                  FButton(
                    onPress: () => showKnowledgeCaptureSheet(context),
                    child: Text(l10n.knowledgeCaptureAction),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: shellTabContentPadding(context),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s10),
          itemBuilder: (context, index) => _NoteTile(note: items[index]),
        );
      },
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      onPress: () => context.push(KnowledgeRoutes.note(note.id)),
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
            style: context.theme.typography.body.md,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (note.bodyMd.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(
              note.bodyMd.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
          if (note.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s10),
            Wrap(
              spacing: AppSpacing.s6,
              children: note.tags
                  .take(5)
                  .map((tag) => FBadge(child: Text(tag)))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}
