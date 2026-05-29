/// Shared helpers for the `propose_inbox_*` tool trio
/// (`docs/knowledgeos-domain.md` §4 + §7).
///
/// Each tool's `invoke` produces a [ProposalEnvelope] map *and* persists
/// the same envelope into the local `knowledge_inbox_triage` side-table
/// so the Review tab "AI 建议" card can render it without a second
/// round-trip. Persistence is delegated here so the three tool files
/// stay focused on schema + payload shaping.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_tool_support.dart';

// The generic envelope / error / preview helpers live in `_tool_support.dart`;
// re-exported here so the inbox `propose_*` trio that already imports this
// file keeps a single import.
export '_tool_support.dart' show proposalEnvelope, badRequest, notePreview;

/// Look up the target note + verify owner. Returns either the note or
/// a `bad_request` envelope to short-circuit the tool.
Future<({KnowledgeNote? note, Map<String, Object?>? error})>
loadOwnedNote(DeviceToolContext ctx, String noteId) async {
  if (noteId.isEmpty) {
    return (note: null, error: badRequest('note_id 必填。'));
  }
  final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
  final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
  final note = await repo.findNote(noteId);
  if (note == null || note.sync.ownerUserId != ownerUserId) {
    return (
      note: null,
      error: badRequest('note_id $noteId 不存在或不属于当前用户。'),
    );
  }
  return (note: note, error: null);
}

/// Persist the envelope into `knowledge_inbox_triage`, merging with any
/// existing record so the Review tab shows all three proposal kinds
/// against the same note. Honours dismissed-kind rule from §7:
/// re-proposing a dismissed kind is a no-op (the dismissed envelope
/// stays).
Future<void> persistEnvelope({
  required DeviceToolContext ctx,
  required String noteId,
  required String ownerUserId,
  required InboxProposalKind kind,
  required String summaryZh,
  required Map<String, Object?> payload,
}) async {
  final triage = await ctx.ref.read(inboxTriageRepositoryProvider.future);
  final now = DateTime.now().toUtc();
  final existing = await triage.findForNote(noteId);
  final fresh = InboxProposal(
    kind: kind,
    summaryZh: summaryZh,
    payload: payload,
    status: InboxProposalStatus.pending,
  );

  final merged = <InboxProposal>[];
  var replaced = false;
  for (final p in existing?.proposals ?? const <InboxProposal>[]) {
    if (p.kind == kind) {
      if (p.status == InboxProposalStatus.dismissed) {
        // §7: dismissed 提议不再重提 — keep the user's verdict.
        merged.add(p);
      } else {
        merged.add(fresh);
      }
      replaced = true;
    } else {
      merged.add(p);
    }
  }
  if (!replaced) merged.add(fresh);

  await triage.upsert(
    InboxTriageRecord(
      noteId: noteId,
      ownerUserId: ownerUserId,
      lastTriagedAt: now,
      proposals: merged,
    ),
  );
}
