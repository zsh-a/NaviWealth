/// KnowledgeOS Riverpod wiring (`docs/knowledgeos-domain.md` §3).
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/llm_credentials/providers.dart'
    show llmCredentialsProvider;
import '../../../core/ai/local/memory/providers.dart'
    show memoryRuntimeProvider;
import '../../../core/auth/current_user.dart';
import '../../../core/logging/providers.dart' show loggerProvider;
import '../../../core/persistence/providers.dart';
import '../../../core/sync/outbox_provider.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ai_chat/data/providers.dart' show deviceLlmClientProvider;
import '../domain/knowledge_models.dart';
import 'capture_classifier.dart';
import 'contradiction_judge.dart';
import 'inbox_triage_classifier.dart';
import 'inbox_triage_repository.dart';
import 'knowledge_repository.dart';
import 'knowledge_search_service.dart';
import 'llm_capture_classifier.dart';
import 'llm_contradiction_judge.dart';
import 'llm_inbox_triage_classifier.dart';

/// Single Uuid instance shared by every KnowledgeOS writer / tool.
/// Replaces a handful of per-file `_kUuid` / `kInboxTriageUuid`
/// declarations — Uuid is stateless, no reason to hold several.
const Uuid kKnowledgeUuid = Uuid();

final knowledgeRepositoryProvider = FutureProvider<KnowledgeRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  return KnowledgeRepository(db: db, outbox: outbox);
});

final knowledgeOwnerUserIdProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(currentUserIdProvider)();
});

final knowledgeInboxNotesProvider =
    StreamProvider.autoDispose<List<KnowledgeNote>>((ref) async* {
      final ownerUserId = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      yield* repository.watchNotes(ownerUserId: ownerUserId, limit: 50);
    });

final knowledgeSearchServiceProvider = FutureProvider<KnowledgeSearchService>((
  ref,
) async {
  final repository = await ref.watch(knowledgeRepositoryProvider.future);
  final memoryRuntime = await ref.watch(memoryRuntimeProvider.future);
  final l10n = _knowledgeDataL10n(ref.watch(localeProvider));
  return KnowledgeSearchService(
    repository: repository,
    memoryRuntime: memoryRuntime,
    displayCopy: KnowledgeSearchDisplayCopy(
      untitled: l10n.knowledgeUntitled,
      routineInterval: (statement, intervalDays) =>
          l10n.knowledgeReviewRoutineMeta(statement, intervalDays),
    ),
  );
});

AppLocalizations _knowledgeDataL10n(Locale? preferred) {
  final locale = preferred ?? PlatformDispatcher.instance.locale;
  final supported = locale.languageCode == 'zh'
      ? const Locale('zh')
      : const Locale('en');
  return lookupAppLocalizations(supported);
}

final inboxTriageRepositoryProvider = FutureProvider<InboxTriageRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return InboxTriageRepository(db: db);
});

/// Inbox-triage classifier seam (§14.2 "InboxTriageAgent LLM round-trip
/// 替换 heuristic"). Returns the LLM-backed classifier when a device LLM
/// profile is configured, the pure-Dart heuristic otherwise. The LLM
/// path degrades silently to the same heuristic on any per-note failure
/// (no profile / network / 8s timeout / parse / low confidence), so the
/// no-LLM (Web / no key) path behaves byte-for-byte as before. Resolved
/// by [InboxTriageAgent.run] via `ctx.ref` so the agent stays
/// synchronously constructible.
final inboxTriageClassifierProvider = FutureProvider<InboxTriageClassifier>((
  ref,
) async {
  final logger = ref.watch(loggerProvider);
  final client = ref.watch(deviceLlmClientProvider);
  if (client == null) {
    logger.i(
      '[inbox-triage] classifier=heuristic — ${_diagnoseLlmUnavailable(ref)}',
    );
    return const HeuristicInboxTriageClassifier();
  }
  logger.i('[inbox-triage] classifier=llm model=${client.config.model}');
  return LlmInboxTriageClassifier(client: client, logger: logger);
});

/// Contradiction-judge seam (§14.2 "ContradictionAgent cosine + LLM
/// judge 路径"). Returns the LLM-backed judge when a device LLM profile
/// is configured, the pure-Dart marker heuristic otherwise. The LLM path
/// degrades silently to the same heuristic on any per-pair failure (no
/// profile / network / timeout / parse / low confidence), so the no-LLM
/// (Web / no key) path stays deterministic. Resolved by
/// [ContradictionAgent.run] via `ctx.ref` so the agent stays
/// synchronously constructible (the agent list is sync, the client is
/// async — same constraint as InboxTriageAgent).
final contradictionJudgeProvider = FutureProvider<ContradictionJudge>((
  ref,
) async {
  final logger = ref.watch(loggerProvider);
  final client = ref.watch(deviceLlmClientProvider);
  if (client == null) {
    logger.i(
      '[contradiction] judge=heuristic — ${_diagnoseLlmUnavailable(ref)}',
    );
    return const HeuristicContradictionJudge();
  }
  logger.i('[contradiction] judge=llm model=${client.config.model}');
  return LlmContradictionJudge(client: client, logger: logger);
});

/// Capture classifier seam. Returns the LLM-driven classifier when a
/// device LLM profile is configured; falls back to the deterministic
/// heuristic otherwise. The LLM classifier internally degrades to the
/// same heuristic on any per-call failure (network / timeout / parse),
/// so call sites never observe an exception out of `classify`.
///
/// CaptureSheet + `propose_capture` tool both read this provider, so
/// the AI-native upgrade UX and the AI tool surface share one
/// classifier instance — matching the §4 "tools mirror UI" contract.
///
/// Build-time logs (tag `[capture]`) record which implementation was
/// chosen so the user can grep the Talker history to confirm whether
/// LLM is actually engaged.
final captureClassifierProvider = Provider<CaptureClassifier>((ref) {
  final logger = ref.watch(loggerProvider);
  // Depend on the client, NOT the full runtime: the `propose_capture`
  // tool reads this provider through the runtime's dispatcher `ref`, and
  // depending on `deviceLlmRuntimeProvider` here would make the runtime
  // transitively depend on itself (CircularDependencyError). The client
  // provider carries no dispatcher/tools, so the graph stays acyclic.
  final client = ref.watch(deviceLlmClientProvider);
  if (client == null) {
    // Drill into the gate chain so the log line tells the user which of
    // the 4 possible reasons fired (web platform / credentials still
    // loading / no active profile / active profile has empty key).
    final reason = _diagnoseLlmUnavailable(ref);
    logger.i('[capture] classifier=heuristic — $reason');
    return const HeuristicCaptureClassifier();
  }
  logger.i('[capture] classifier=llm model=${client.config.model}');
  return LlmCaptureClassifier(client: client, logger: logger);
});

String _diagnoseLlmUnavailable(Ref ref) {
  if (kIsWeb) {
    return 'platform=web (LLM gated to native by deviceLlmPlatformSupportedProvider)';
  }
  final credsAsync = ref.watch(llmCredentialsProvider);
  if (credsAsync.isLoading) {
    return 'credentials still loading from secure storage '
        '(reopen the sheet after a moment)';
  }
  if (credsAsync.hasError) {
    return 'credentials load errored: ${credsAsync.error}';
  }
  final creds = credsAsync.asData?.value;
  if (creds == null) {
    return 'credentials store returned null (unexpected — check llmCredentialStoreProvider)';
  }
  final active = creds.active;
  if (active == null) {
    return 'no active profile selected '
        '(profiles configured: ${creds.profiles.length}, '
        'activeId=${creds.activeId ?? "(null)"}) — '
        'go to Settings → AI 一键选一个';
  }
  if (!active.hasKey) {
    final keyLen = active.apiKey.length;
    return 'active profile "${active.id}" (${active.provider.name}) '
        'has empty apiKey (raw length=$keyLen, trim is empty) — '
        '回 Settings 把 API key 填一下并保存';
  }
  return 'unknown reason (runtime null but credentials look usable — '
      'likely a transient build race; rebuild should fix)';
}
