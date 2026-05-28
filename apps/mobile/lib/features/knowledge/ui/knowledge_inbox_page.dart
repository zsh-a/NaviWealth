/// KnowledgeOS Inbox tab (`docs/knowledgeos-domain.md` §5).
///
/// Renders captured Notes. The FAB opens [showKnowledgeCaptureSheet] —
/// a unified AI-native capture (single textarea + post-save inline
/// upgrade suggestion). The old typed `_NewNoteSheet` is gone; promoting
/// a capture to Decision / Routine / etc. happens through the inline
/// upgrade card in the sheet itself, not by picking the type up front.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_capture_sheet.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      header: const FHeader.nested(title: Text('收件箱 · KnowledgeOS')),
      childPad: false,
      child: Stack(
        children: [
          const Positioned.fill(child: _InboxBody()),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: FButton(
              prefix: const Icon(FLucideIcons.plus, size: 16),
              onPress: () => showKnowledgeCaptureSheet(context, ref),
              child: const Text('新建捕获'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxBody extends ConsumerWidget {
  const _InboxBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(knowledgeRepositoryProvider);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const _Centered(child: FProgress());
        final owner = ownerSnap.data!;
        return repoAsync.when(
          loading: () => const _Centered(child: FProgress()),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (repo) {
            return StreamBuilder<List<KnowledgeNote>>(
              stream: repo.watchNotes(ownerUserId: owner, limit: 50),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <KnowledgeNote>[];
                if (notes.isEmpty) return const _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s8,
                    AppSpacing.s16,
                    // Bottom padding leaves room for the floating FAB.
                    AppSpacing.s64,
                  ),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s8),
                  itemBuilder: (context, i) => _NoteCard(note: notes[i]),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final KnowledgeNote note;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? '(无标题)' : note.title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (note.bodyMd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              note.bodyMd.length > 200
                  ? '${note.bodyMd.substring(0, 200)}…'
                  : note.bodyMd,
              style: typography.sm.copyWith(color: colors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.inbox_outlined,
      title: '收件箱空空如也',
      message: '点击右下角 + 写一条想法 — AI 会判断它是 Note / Routine / Decision，'
          '一键确认升级。',
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return AppEmptyState.error(
      title: '收件箱加载失败',
      message: message,
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
