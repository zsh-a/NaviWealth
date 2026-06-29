import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../../core/ai/composition/chat_trace_prep.dart';
import '../../../core/ai/composition/device_tools_provider.dart';
import '../../../core/ai/composition/portfolio_snapshot.dart';
import '../../../core/ai/composition/system_prompt_blocks.dart';
import '../../../core/ai/llm_credentials/llm_credentials.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/ai/runtime/device/anthropic/anthropic_client.dart';
import '../../../core/ai/runtime/device/openai/openai_client.dart';
import '../../../core/ai/runtime/device/tools/device_tool_registry.dart';
import '../../../core/ai/trace/trace.dart';
import '../../../core/auth/providers.dart';
import '../../../core/logging/providers.dart';
import '../../../core/persistence/providers.dart';
import '../domain/chat_models.dart';
import 'ai_chat_api_client.dart';
import 'chat_history_store.dart';
import 'chat_repository.dart';
import 'runtime_routing_api_client.dart';

/// Just the provider-neutral LLM **client** (or `null` when unavailable),
/// split out of [deviceLlmRuntimeProvider] so lightweight consumers (e.g.
/// `captureClassifierProvider`) can depend on the client WITHOUT pulling
/// in the agent loop's dispatcher + tool registry.
///
/// This split is what breaks a circular dependency: the runtime's
/// dispatcher holds the runtime provider's `ref`, and a dispatched tool
/// (`propose_capture`) reads `captureClassifierProvider`. If that
/// classifier depended on `deviceLlmRuntimeProvider`, the runtime would
/// transitively depend on itself. Depending on the client provider
/// instead keeps the graph acyclic.
final deviceLlmClientProvider = Provider<DeviceLlmClient?>((ref) {
  if (!ref.watch(deviceLlmAvailableProvider)) return null;
  final profile = ref.watch(llmCredentialsProvider).asData?.value?.active;
  if (profile == null || !profile.hasKey) return null;
  // Each instance gets its own [Dio] because the base URL is the user's
  // (possibly custom) endpoint.
  final dio = Dio()
    ..interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  return switch (profile.provider) {
    LlmProvider.anthropic => AnthropicClient(
      dio: dio,
      config: LlmConfig.fromProfile(profile),
    ),
    LlmProvider.openai => OpenAiClient(
      dio: dio,
      config: OpenAiConfig.fromProfile(profile),
    ),
  };
});

/// The on-device runtime, or `null` when unavailable (web /
/// no active profile). Rebuilt automatically when the active profile
/// changes, since [deviceLlmClientProvider] (which watches
/// [deviceLlmAvailableProvider] / [llmCredentialsProvider]) is watched.
final deviceLlmRuntimeProvider = Provider<DeviceLlmRuntime?>((ref) {
  final client = ref.watch(deviceLlmClientProvider);
  if (client == null) return null;
  // §4.6.3 — registry membership is the device allow-list. The list
  // itself is built by the cross-domain composition root
  // ([deviceToolsProvider], `docs/architecture/lifeos-shell.md` §7.1 D-1.2): each
  // active LifeOS domain registers its own tools via a Riverpod
  // override in `bootstrap.dart`. Tools not yet ported simply aren't
  // advertised, so the model never calls them.
  final tools = ref.watch(deviceToolsProvider);
  final registry = DeviceToolRegistry(tools);
  // Phase D domain-aware prompt: base + each active domain's block,
  // assembled by the composition seam in lockstep with the tool list.
  final basePrompt = ref.watch(assembledSystemPromptProvider);
  return DeviceLlmRuntime(
    client: client,
    dispatcher: DriftDeviceToolDispatcher(ref: ref, registry: registry),
    toolSchemas: registry.schemas(),
    basePrompt: basePrompt,
  );
});

/// What `ChatRepository` injects before app-level composition.
///
/// Production bootstrap overrides this provider with [FrbChatRunner] when an
/// active FRB LLM profile exists. The feature-layer default deliberately stays
/// unavailable so a partial ProviderContainer cannot silently fall back to the
/// legacy direct-Dart LLM runtime.
final aiChatApiClientProvider = Provider<AiChatApiClient>((ref) {
  return const RuntimeRoutingAiChatApiClient();
});

/// Chat persistence is awaited once via [appDatabaseProvider]. We expose
/// the store as an `AsyncValue` so consumers can react to first-time DB
/// boot the same way the rest of the app does.
final chatHistoryStoreProvider = FutureProvider<ChatHistoryStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final store = ChatHistoryStore(db);
  ref.onDispose(store.dispose);
  return store;
});

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final store = await ref.watch(chatHistoryStoreProvider.future);
  final api = ref.watch(aiChatApiClientProvider);
  final reader = ref.watch(authSessionReaderProvider);
  final traceStore = ref.watch(aiTraceStoreProvider);
  final tracePrep = ref.watch(chatTracePrepProvider);
  final portfolioReader = ref.watch(portfolioSnapshotReaderProvider);
  return ChatRepository(
    store: store,
    api: api,
    sessionReader: reader,
    portfolioSnapshotReader: portfolioReader,
    tracePrep: tracePrep,
    traceStore: traceStore,
  );
});

/// Streamed list of all chat sessions for [ownerUserId]. Sidebar UI
/// watches this directly; one stream per user partition.
final chatSessionsStreamProvider =
    StreamProvider.family<List<ChatSession>, String>((ref, ownerUserId) async* {
      final repo = await ref.watch(chatRepositoryProvider.future);
      yield* repo.watchSessions(ownerUserId);
    });

/// Streamed message timeline for a single session. The chat page
/// watches this; updates fire after every SSE frame.
final chatMessagesStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, sessionId) async* {
      final repo = await ref.watch(chatRepositoryProvider.future);
      yield* repo.watchMessages(sessionId);
    });
