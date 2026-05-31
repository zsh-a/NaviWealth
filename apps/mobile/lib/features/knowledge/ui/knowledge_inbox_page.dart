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

import '../../../app/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/ui/ask_ai.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';
import 'knowledge_capture_sheet.dart';

class KnowledgeInboxPage extends ConsumerWidget {
  const KnowledgeInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellTabScaffold(
      title: '收件箱 · KnowledgeOS',
      child: Stack(
        children: [
          const Positioned.fill(child: _InboxBody()),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: FButton(
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
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
    // The Inbox is the KnowledgeOS "AI 助理" front door: the bar stays
    // pinned above the note list (visible even while loading / empty) so
    // add / query / dedupe / suggest are always one tap away.
    return const Column(
      children: [
        _AiAssistantBar(),
        Expanded(child: _NotesList()),
      ],
    );
  }
}

/// The agent entry: a tappable ask/capture pill + three quick-action
/// chips. Each routes through `askAi` conversation mode, which (on the
/// knowledge route) opens the device agent loop scoped to KnowledgeOS
/// tools + prompt with the composer seeded. The user sends; the agent
/// then chains the right tools:
///
///  - pill     → empty composer (type a capture or a question freeform)
///  - 查重     → seeds dedupe (agent → find_similar_knowledge → propose_merge)
///  - 本周建议 → seeds suggest (agent → review_knowledge_health → propose_*)
///  - 搜知识   → seeds cross-type search (agent → search_knowledge)
///
/// Conversation prefill (not auto-fired invocation intents) keeps this
/// off the regression-corpus / renderer fixture path while still
/// delivering the full agentic loop on send.
class _AiAssistantBar extends ConsumerWidget {
  const _AiAssistantBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s4, ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => askAi(context, ref, prefill: ''),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s12,
              ),
              child: Row(
                children: [
                  Icon(FLucideIcons.sparkles, size: AppIconSizes.sm, color: colors.primary),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      '记点什么 / 问点什么…',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                  Icon(
                    FLucideIcons.arrowRight,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              _Chip(
                label: '查重',
                icon: FLucideIcons.gitMerge,
                onTap: () => askAi(
                  context,
                  ref,
                  prefill:
                      '帮我查一下知识库里有没有内容相近、可能重复的笔记或概念，'
                      '重复的建议合并。',
                ),
              ),
              _Chip(
                label: '本周建议',
                icon: FLucideIcons.lightbulb,
                onTap: () => askAi(
                  context,
                  ref,
                  prefill:
                      '根据我的知识库给我这周的建议：到期复盘的决策、'
                      '长期未校验的假设、本周到期的定期事项、没有标签或链接的孤儿笔记。',
                ),
              ),
              _Chip(
                label: '搜知识',
                icon: FLucideIcons.search,
                onTap: () => askAi(context, ref, prefill: '搜索我的知识库：'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FButton(
      variant: FButtonVariant.outline,
      onPress: onTap,
      prefix: Icon(icon, size: AppIconSizes.xs),
      child: Text(label),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

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
                  padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, // Bottom padding leaves room for the floating FAB.
                    AppSpacing.s64, ),
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
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (note.bodyMd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              knowledgeExcerpt(note.bodyMd),
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
      icon: FLucideIcons.inbox,
      title: '收件箱空空如也',
      message:
          '点击右下角 + 写一条想法 — AI 会判断它是 Note / Routine / Decision，'
          '一键确认升级。',
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return AppEmptyState.error(title: '收件箱加载失败', message: message);
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
