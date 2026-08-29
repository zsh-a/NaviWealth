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

enum _LibraryView { notes, decisions }

class KnowledgeLibraryPage extends ConsumerStatefulWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  ConsumerState<KnowledgeLibraryPage> createState() =>
      _KnowledgeLibraryPageState();
}

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage> {
  var _view = _LibraryView.notes;

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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s12,
                AppSpacing.s16,
                0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_LibraryView>(
                  segments: <ButtonSegment<_LibraryView>>[
                    ButtonSegment<_LibraryView>(
                      value: _LibraryView.notes,
                      icon: const Icon(Icons.notes),
                      label: Text(l10n.knowledgeSegmentNotes),
                    ),
                    ButtonSegment<_LibraryView>(
                      value: _LibraryView.decisions,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(l10n.knowledgeSegmentDecisions),
                    ),
                  ],
                  selected: <_LibraryView>{_view},
                  onSelectionChanged: (value) =>
                      setState(() => _view = value.single),
                ),
              ),
            ),
            Expanded(
              child: _view == _LibraryView.notes
                  ? _LibraryNotes(ref.watch(knowledgeNotesProvider))
                  : _LibraryDecisions(ref.watch(knowledgeDecisionsProvider)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryNotes extends StatelessWidget {
  const _LibraryNotes(this.value);

  final AsyncValue<List<KnowledgeNote>> value;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) =>
        Center(child: Text(AppLocalizations.of(context).commonLoadFailed)),
    data: (notes) => _LibraryList(
      emptyLabel: AppLocalizations.of(context).knowledgeInboxEmptyTitle,
      children: notes
          .map(
            (note) => _LibraryTile(
              title: note.title.isEmpty
                  ? AppLocalizations.of(context).knowledgeUntitled
                  : note.title,
              subtitle: note.bodyMd,
              icon: FLucideIcons.fileText,
              onPress: () => context.push(KnowledgeRoutes.note(note.id)),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _LibraryDecisions extends StatelessWidget {
  const _LibraryDecisions(this.value);

  final AsyncValue<List<KnowledgeDecision>> value;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) =>
        Center(child: Text(AppLocalizations.of(context).commonLoadFailed)),
    data: (decisions) => _LibraryList(
      emptyLabel: AppLocalizations.of(context)
          .knowledgeLibraryEmptyDecisionsTitle,
      children: decisions
          .map(
            (decision) => _LibraryTile(
              title: decision.question,
              subtitle: decision.selectedLabel,
              icon: FLucideIcons.circleCheck,
              onPress: () =>
                  context.push(KnowledgeRoutes.decision(decision.id)),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.emptyLabel, required this.children});

  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return Center(child: Text(emptyLabel));
    return ListView.separated(
      padding: shellTabContentPadding(context),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s10),
      itemBuilder: (_, index) => children[index],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPress,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        children: [
          Icon(icon, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.theme.typography.body.md),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    subtitle.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
