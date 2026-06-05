/// KnowledgeOS contribution to the cross-domain chat rail
/// (`docs/lifeos-shell.md` §4 + `docs/knowledgeos-domain.md` §6).
///
/// Builds a list of Recall chip suggestions surfaced inside the AI
/// chat rail when the Knowledge domain is opt-in. Each chip points at
/// a Decision via a free-text headline so the user can tap to recall
/// the rationale without retyping the question.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/composition/chat_rail_content.dart';
import '../../../core/auth/current_user.dart';
import '../data/providers.dart';

/// Build the rail content for the active user. Async because the repo
/// future has to resolve; consumers should treat an empty list as the
/// not-yet-loaded state.
final knowledgeChatRailContentProvider = FutureProvider<List<ChatRailContent>>((
  ref,
) async {
  final repo = await ref.watch(knowledgeRepositoryProvider.future);
  final ownerUserId = await ref.read(currentUserIdProvider)();

  final decisions = await repo.listDecisions(
    ownerUserId: ownerUserId,
    limit: 50,
  );
  if (decisions.isEmpty) return const <ChatRailContent>[];

  return decisions
      .take(3)
      .map(
        (d) => ChatRailContent(
          id: 'knowledge:decision:${d.id}',
          headline: d.question.length > 60
              ? '${d.question.substring(0, 60)}…'
              : d.question,
          detail: d.rationaleMd.isEmpty
              ? d.selectedLabel
              : (d.rationaleMd.length > 140
                    ? '${d.rationaleMd.substring(0, 140)}…'
                    : d.rationaleMd),
          icon: FLucideIcons.brain,
          route: AppRoutes.knowledgeLibrary,
        ),
      )
      .toList(growable: false);
});
