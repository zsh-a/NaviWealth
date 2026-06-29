import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/llm_credentials/providers.dart' as llm_credentials;
import '../core/ai/local/embedding/embedder.dart';
import '../core/ai/local/embedding/embedder_path_resolution.dart';
import '../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../core/ai/local/memory/providers.dart' as memory_providers;
import '../core/auth/providers.dart' as core_auth;
import '../core/config/app_config.dart';
import '../core/config/providers.dart';
import '../core/format/formatters.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/crash_reporter.dart';
import '../core/logging/logging_crash_reporter.dart';
import '../core/logging/providers.dart';
import '../core/logging/sentry_crash_reporter.dart';
import '../core/notifications/notification_preferences.dart';
import '../core/notifications/providers.dart' as notif_providers;
import '../core/perf/providers.dart';
import '../core/sync/providers.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/activity/data/activity_entry_insight_client.dart';
import '../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../features/ai_chat/data/runtime_routing_api_client.dart';
import '../features/auth/data/auth_controller.dart';
import '../features/auth/data/auth_route_guard.dart';
import '../features/cashflow/data/recurring_transaction_providers.dart';
import '../features/execution/agents/providers.dart'
    as execution_agent_providers;
import '../features/execution/agents/review_agent.dart';
import '../features/finance/data/market/sync/price_sync_providers.dart';
import '../features/health/agents/briefing_synthesizer.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/agents/providers.dart' as health_agent_providers;
import '../features/health/agents/recovery_alert_agent.dart';
import '../features/health/agents/weekly_summary_agent.dart';
import '../features/health/data/morning_briefing_preferences.dart';
import '../features/ingest/data/ingest_llm_client.dart';
import '../features/knowledge/agents/assumption_agent.dart';
import '../features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import '../features/knowledge/agents/review_agent.dart';
import '../features/knowledge/agents/routine_due_agent.dart';
import '../features/knowledge/data/knowledge_llm_client.dart';
import '../l10n/gen/app_localizations.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_llm_bridge.dart';
import 'agent_runtime_llm_stream_bridge.dart';
import 'agent_runtime_native_bridge.dart';
import 'agent_runtime_runner.dart';
import 'agent_runtime_tool_host.dart';
import 'agent_runtime_trace_recorder.dart';
import 'domain_composition.dart';
import 'frb_chat_runner.dart';
import 'frb_llm_connectivity_probe.dart';
import 'memory_indexers_bootstrap.dart';
import 'route_guard.dart';

/// Initializes the app shell: framework binding, URL strategy, and the global
/// error pipeline (Flutter framework errors, async zone errors, and the
/// platform dispatcher channel) all funnel through [AppLogger] → [CrashReporter].
///
/// Returns a [ProviderContainer] pre-seeded with the bootstrap logger and a
/// warm [SharedPreferences] handle so theme/market-color preferences resolve
/// synchronously on first build. The caller hosts it inside
/// `UncontrolledProviderScope`.
Future<ProviderContainer> bootstrap({AppConfig? config}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean URLs on web (e.g. /portfolio instead of /#/portfolio).
  // No-op elsewhere.
  usePathUrlStrategy();
  await AppFormatters.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final effectiveConfig = config ?? AppConfig.dev;
  final sentryReady = await initializeSentryCrashReporter(effectiveConfig);

  // Resolve embedder asset paths before the container is built
  // so the override list knows whether to wire the Rust embedder. Each
  // path can come from either an `AppConfig` dart-define override (dev
  // / test) or from the in-app installer's on-disk install dir. When
  // any required path is missing we leave `embedderProvider` on its
  // [StubEmbedder] default and let the user install the bundle from
  // Settings → AI Models.
  final resolvedEmbedderPaths = await resolveEmbedderPaths(effectiveConfig);

  final container = ProviderContainer(
    overrides: [
      if (config != null) appConfigProvider.overrideWithValue(config),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // `roadmap-next.md` §3.6 — Sentry is installed only when a build
      // supplies SENTRY_DSN and SDK init succeeds. Otherwise debug builds
      // keep routing captureError / breadcrumbs through Talker so engineers
      // can verify the opt-in pipeline without shipping telemetry.
      if (sentryReady)
        crashReporterDelegateProvider.overrideWithValue(
          const SentryCrashReporter(),
        )
      else if (kDebugMode)
        crashReporterDelegateProvider.overrideWith(
          (ref) => LoggingCrashReporter(talker: ref.watch(talkerProvider)),
        ),
      // Plug the AuthRouteGuard into the empty default. The guard
      // reads `authControllerProvider` per redirect; auth state changes
      // bump `routeRedirectVersionProvider` which makes go_router re-run
      // the full redirect chain. Skipped when `bypassAuth` is on so dev
      // builds can browse the app without a session.
      routeGuardsProvider.overrideWith(
        (ref) => <RouteGuard>[
          if (!effectiveConfig.bypassAuth) ref.watch(authRouteGuardProvider),
          ref.watch(domainOptInRouteGuardProvider),
        ],
      ),
      llm_credentials.llmConnectivityProbeProvider.overrideWith(
        (ref) => FrbLlmConnectivityProbe(
          bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        ),
      ),
      ai_chat_providers.aiChatApiClientProvider.overrideWith((ref) {
        final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
        final streamBridge = ref.watch(agentRuntimeLlmStreamBridgeProvider);
        if (llmBridge != null && streamBridge != null) {
          final catalog = ref.watch(agentRuntimeCatalogProvider);
          final toolHost = ref.watch(agentRuntimeToolHostProvider);
          return RuntimeRoutingAiChatApiClient(
            device: FrbChatRunner(
              llmBridge: llmBridge,
              streamBridge: streamBridge,
              tools: [for (final tool in catalog.tools) tool.toJson()],
              toolLineHandler: toolHost.handleLine,
            ),
          );
        }
        return const RuntimeRoutingAiChatApiClient();
      }),
      activityEntryInsightClientProvider.overrideWith((ref) {
        final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
        return llmBridge == null
            ? null
            : FrbActivityEntryInsightClient(llmBridge: llmBridge);
      }),
      knowledgeLlmProfileClientProvider.overrideWith((ref) {
        final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
        return llmBridge == null
            ? null
            : FrbKnowledgeLlmProfileClient(
                llmBridge: llmBridge,
                recordTrace: ref
                    .read(agentRuntimeTraceRecorderProvider)
                    .recordProfileCompletion,
              );
      }),
      ingestLlmProfileClientProvider.overrideWith((ref) {
        final llmBridge = ref.watch(agentRuntimeLlmBridgeProvider);
        return llmBridge == null
            ? null
            : FrbIngestLlmProfileClient(
                llmBridge: llmBridge,
                recordTrace: ref
                    .read(agentRuntimeTraceRecorderProvider)
                    .recordProfileCompletion,
              );
      }),
      // Feed the access token to the SyncEngine so /sync/push and
      // /sync/pull go out authed once a session is active. The fetcher
      // closes over Riverpod's container, so token rotation is picked up
      // on every request without re-creating the SyncEngine.
      syncAuthTokenProvider.overrideWith(
        (ref) =>
            () async => ref
                .read(authControllerProvider.notifier)
                .currentSession()
                ?.accessToken,
      ),
      // Wire the AuthInterceptor's hooks to the live controller so any
      // future `authedDioProvider` consumer (feature endpoints that need
      // refresh-on-401) gets the correct session + recovery behaviour.
      core_auth.authSessionReaderProvider.overrideWith(
        (ref) =>
            () => ref.read(authControllerProvider.notifier).currentSession(),
      ),
      core_auth.authSessionProvider.overrideWith((ref) {
        final state = ref.watch(authControllerProvider).value;
        return state is AuthLoggedIn ? state.session : null;
      }),
      core_auth.authStateProvider.overrideWith(
        (ref) => ref.watch(authControllerProvider).value,
      ),
      core_auth.authOnUnauthorizedProvider.overrideWith(
        (ref) =>
            () => ref.read(authControllerProvider.notifier).refreshIfPossible(),
      ),
      core_auth.domainOptInTokenRefreshProvider.overrideWith(
        (ref) => () async {
          await ref.read(authControllerProvider.notifier).refreshIfPossible();
        },
      ),
      // LifeOS domain inventory + active-domain aggregators
      // (`docs/architecture/lifeos-shell.md` §4): tools, prompt blocks, agents, shell
      // specs, domain provider seams, and the registry all derive from
      // the DomainPack list.
      ...lifeOsDomainCompositionOverrides(),
      // Execution Review is a tool-using production agent. Route its read
      // snapshot through FRB `tool_plan` steps while keeping weekly/today
      // summarisation and memory writes in Dart.
      execution_agent_providers.executionReviewAgentProvider.overrideWith((
        ref,
      ) {
        return ExecutionReviewAgent(
          reviewReader: FrbExecutionReviewReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kExecutionReviewAgentId,
                    stepRun: stepRun,
                    domain: 'execution',
                    surface: 'execution_review',
                  );
            },
          ),
        );
      }),
      // Wire the Morning Briefing with the FRB-backed LLM synthesizer
      // first, then programmatic fallback when FRB/profile is unavailable.
      // and the local notification service so each successful run can
      // surface a toast even when the app is backgrounded. The agent
      // itself stays composition-blind; this is the seam where the
      // shell decides "use which synthesis + which notifier".
      morningBriefingAgentProvider.overrideWith((ref) {
        final frbRunner = ref.watch(agentRuntimeProfileTurnRunnerProvider);
        final notificationsEnabled = ref.watch(notificationsEnabledProvider);
        final briefingNotificationsEnabled = ref.watch(
          healthBriefingNotificationsEnabledProvider,
        );
        final notifier = notificationsEnabled && briefingNotificationsEnabled
            ? ref.watch(notif_providers.notificationServiceProvider)
            : null;
        final hourLocal = ref.watch(morningBriefingHourProvider);
        final BriefingSynthesizer synth = frbRunner != null
            ? FrbBriefingSynthesizer(
                runner: frbRunner,
                recordTrace: (result) {
                  return ref
                      .read(agentRuntimeTraceRecorderProvider)
                      .recordProfileTurn(
                        agentId: 'morning_briefing',
                        result: result,
                        domain: 'health',
                        surface: 'health_morning_briefing',
                      );
                },
                fallback: const ProgrammaticBriefingSynthesizer(),
              )
            : const ProgrammaticBriefingSynthesizer();
        return MorningBriefingAgent(
          synthesizer: synth,
          notifier: notifier,
          hourLocal: hourLocal,
        );
      }),
      // Route the tool-using Recovery Alert production agent through the
      // FRB native step runner first. The native runner requests
      // `get_hrv_trend` through a `tool_plan`; Dart still executes the device
      // tool against Riverpod/Drift, and the agent falls back to direct
      // repository reads if the embedded runtime path is unavailable.
      recoveryAlertAgentProvider.overrideWith((ref) {
        final notificationsEnabled = ref.watch(notificationsEnabledProvider);
        final briefingNotificationsEnabled = ref.watch(
          healthBriefingNotificationsEnabledProvider,
        );
        final notifier = notificationsEnabled && briefingNotificationsEnabled
            ? ref.watch(notif_providers.notificationServiceProvider)
            : null;
        return RecoveryAlertAgent(
          notifier: notifier,
          signalReader: FrbRecoveryAlertSignalReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kRecoveryAlertAgentId,
                    stepRun: stepRun,
                    domain: 'health',
                    surface: 'health_recovery_alert',
                  );
            },
          ),
        );
      }),
      // Weekly Summary aggregates HealthOS read tools through the FRB
      // `tool_plan` loop, preserving Dart-side summary/memory policy and
      // repository fallback.
      weeklySummaryAgentProvider.overrideWith((ref) {
        return WeeklySummaryAgent(
          summaryReader: FrbWeeklySummaryReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kWeeklySummaryAgentId,
                    stepRun: stepRun,
                    domain: 'health',
                    surface: 'health_weekly_summary',
                  );
            },
          ),
        );
      }),
      // Knowledge Weekly Review reads two KnowledgeOS datasets. Keep its
      // summary/memory policy in Dart, but route the reads through FRB native
      // `tool_plan` steps so the production path exercises the embedded
      // runtime and local trace capture.
      knowledge_agent_providers.reviewAgentProvider.overrideWith((ref) {
        return ReviewAgent(
          dueReader: FrbReviewDueReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kKnowledgeReviewAgentId,
                    stepRun: stepRun,
                    domain: 'knowledge',
                    surface: 'knowledge_review',
                  );
            },
          ),
        );
      }),
      // Knowledge Assumption Review uses the same embedded FRB tool-plan
      // pattern for `list_open_assumptions`; Dart keeps the stale-threshold
      // policy and memory write.
      knowledge_agent_providers.assumptionAgentProvider.overrideWith((ref) {
        return AssumptionAgent(
          assumptionReader: FrbAssumptionReviewReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kKnowledgeAssumptionAgentId,
                    stepRun: stepRun,
                    domain: 'knowledge',
                    surface: 'knowledge_assumption',
                  );
            },
          ),
        );
      }),
      // Knowledge Routine Due is another tool-using production agent. Route its
      // due-routine read through the same FRB native `tool_plan` loop while
      // preserving the existing repository fallback and notification behavior.
      knowledge_agent_providers.routineDueAgentProvider.overrideWith((ref) {
        final notificationsEnabled = ref.watch(notificationsEnabledProvider);
        final notifier = notificationsEnabled
            ? ref.watch(notif_providers.notificationServiceProvider)
            : null;
        return RoutineDueAgent(
          notifier: notifier,
          dueReader: FrbRoutineDueReader(
            stepRunner: ref.watch(agentRuntimeNativeStepRunnerProvider),
            catalog: ref.watch(agentRuntimeCatalogProvider),
            recordTrace: (stepRun) {
              return ref
                  .read(agentRuntimeTraceRecorderProvider)
                  .recordStepRun(
                    agentId: kKnowledgeRoutineAgentId,
                    stepRun: stepRun,
                    domain: 'knowledge',
                    surface: 'knowledge_routine_due',
                  );
            },
          ),
        );
      }),
      // Swap in the Rust
      // EmbeddingGemma embedder when the user has configured a model
      // directory. Loading is async (FRB init + ONNX session warm-up
      // takes a few seconds); the override returns a Future that the
      // memoryRuntimeProvider awaits. On any failure (missing dylib,
      // missing model, malformed config) we log and fall back to
      // [StubEmbedder] so the app boots regardless.
      if (resolvedEmbedderPaths.isComplete)
        memory_providers.embedderProvider.overrideWith(
          (ref) async => _loadRustEmbedderOrFallback(
            modelDir: resolvedEmbedderPaths.modelDir,
            ortDylibPath: resolvedEmbedderPaths.ortDylibPath,
            libraryPath: resolvedEmbedderPaths.libraryPath,
            logger: ref.read(loggerProvider),
          ),
        ),
    ],
  );
  // Force eager creation so AppLogger.instance is ready before any error
  // handler fires.
  final logger = container.read(loggerProvider);
  if (resolvedEmbedderPaths.isComplete) {
    logger.i(
      'Rust embedder path resolution complete '
      '(modelDir=${resolvedEmbedderPaths.modelDir}, '
      'ortDylibPath=${resolvedEmbedderPaths.ortDylibPath}, '
      'libraryPath=${resolvedEmbedderPaths.libraryPath ?? '<plugin-loader>'})',
    );
  } else {
    logger.i(
      'Rust embedder not configured; using StubEmbedder '
      '(missing: ${resolvedEmbedderPaths.missingInputs.join(', ')})',
    );
  }
  // Eager-init the frame timing collector so the addTimingsCallback
  // subscription is in place before the first frame ships. Otherwise
  // PerfTraceRecorder windows opened at startup would race the first
  // few frames and miss them. `roadmap-next.md` §4 M-5.
  container.read(frameTimingCollectorProvider);

  // Warm up the LLM credentials FutureProvider so the secure-storage
  // load runs in parallel with the first frame instead of cold-starting
  // when the user first taps an AI surface. The Capture sheet
  // (`KnowledgeCaptureSheet`) reads `captureClassifierProvider`
  // synchronously via `ref.read` — if credentials were still loading,
  // it would fall back to the heuristic classifier and never recover
  // for that one save. Fire-and-forget: the actual value is consumed
  // through `ref.watch` chains; we just need the future to start.
  unawaited(container.read(llm_credentials.llmCredentialsProvider.future));

  FlutterError.onError = (details) {
    if (isBenignDuplicateKeyDownAssertion(details)) {
      logger.w(
        'Ignored duplicate platform KeyDown assertion',
        error: details.exception,
        stackTrace: details.stack,
      );
      return;
    }
    logger.e(
      'Uncaught Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };

  if (kDebugMode) {
    logger.i('NaviWealth bootstrap complete (${logger.environment.name})');
    logger.i('API_BASE_URL: ${effectiveConfig.apiBaseUrl}');

    // Network connectivity diagnostic
    final testDio = Dio(
      BaseOptions(
        baseUrl: effectiveConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
      ),
    );
    try {
      final resp = await testDio.get<dynamic>('/health');
      logger.i('Backend health check: ${resp.statusCode} ${resp.data}');
    } on DioException catch (e) {
      logger.e(
        'Backend health check FAILED',
        error: e,
        stackTrace: StackTrace.current,
      );
      logger.e('  type: ${e.type}');
      logger.e('  message: ${e.message}');
      logger.e('  error: ${e.error}');
    }
  }

  // Restore the persisted auth session before bootstrapping foreground sync
  // and startup jobs. Otherwise those jobs can observe the transient
  // "unknown" auth state and fail before the controller has read storage.
  if (!effectiveConfig.bypassAuth) {
    await container.read(authControllerProvider.future);
  }

  // Start foreground data sync. PriceSyncCoordinator owns both quote
  // warming and FX refresh so dashboard valuations have one startup path.
  final authState = container.read(authControllerProvider).value;
  if (authState is AuthLoggedIn || authState is AuthLocalOnly) {
    container.read(syncSchedulerBootstrapProvider);
    container.read(priceSyncCoordinatorBootstrapProvider);
    _scheduleMemoryRuntimeStartupTasks(container: container, logger: logger);
    container.read(memoryLayerBootstrapProvider);
  } else {
    logger.i('Foreground sync startup tasks skipped until auth is ready');
    logger.i('Memory Runtime startup tasks skipped until auth is ready');
    logger.i('Memory Layer indexers skipped until auth is ready');
  }
  // Drive the platform background scheduler from the
  // Health domain opt-in. Eager-read so the provider mounts now
  // and reacts to subsequent toggles (workmanager register / cancel
  // happens inside the provider build, see `morningBriefingCronProvider`).
  container.read(health_agent_providers.morningBriefingCronProvider);
  container.read(health_agent_providers.garminSyncCronProvider);
  container.read(health_agent_providers.healthPlatformSyncCronProvider);
  // When the workmanager callback fired while the app was
  // backgrounded it stamped `kMorningBriefingDueAtKey`. Kick off the
  // in-process run so the freshest summary lands in Memory + the
  // notification gets refined to the actual content.
  unawaited(
    container.read(health_agent_providers.pendingBriefingRunProvider.future),
  );
  unawaited(
    container.read(health_agent_providers.pendingGarminSyncRunProvider.future),
  );
  unawaited(
    container.read(
      health_agent_providers.pendingHealthPlatformSyncRunProvider.future,
    ),
  );
  // Eager startup catch-up for due recurring transactions. This is a
  // local-first finance job (it writes through the mutation stamper /
  // journal repo, no cloud session needed — the same provider runs
  // ungated from Home / CashFlow), so it must fire in local-only mode
  // too, not just when a cloud session exists.
  unawaited(
    container.read(
      recurringMaterialiseDueProvider(DateTime.now().toUtc()).future,
    ),
  );

  return container;
}

class FrbActivityEntryInsightClient implements ActivityEntryInsightClient {
  const FrbActivityEntryInsightClient({
    required AgentRuntimeLlmBridge llmBridge,
  }) : _llmBridge = llmBridge;

  final AgentRuntimeLlmBridge _llmBridge;

  @override
  Future<String?> explain(
    ActivityEntryInsightRequest request,
    AppLocalizations l10n,
  ) async {
    final response = await _llmBridge.completeProfile(
      messages: <Map<String, Object?>>[
        <String, Object?>{
          'role': 'system',
          'content': activityEntryInsightSystem(request.locale),
        },
        <String, Object?>{
          'role': 'user',
          'content': activityEntryInsightPrompt(request, l10n),
        },
      ],
      maxOutputTokens: 256,
      metadata: const <String, Object?>{
        'surface': 'finance_activity_insight',
        'agent_id': 'finance_activity_insight',
      },
    );
    final body = response['content'];
    return body is String ? body : null;
  }
}

typedef FrbProfileCompletionTraceRecorder =
    Future<Object?> Function({
      required String agentId,
      required Map<String, Object?>? llmResponse,
      DateTime? startedAt,
      DateTime? finishedAt,
      String? requestId,
      String domain,
      String surface,
      String routingReason,
      Object? error,
    });

class FrbKnowledgeLlmProfileClient implements KnowledgeLlmProfileClient {
  const FrbKnowledgeLlmProfileClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _llmBridge = llmBridge,
       _recordTrace = recordTrace;

  final AgentRuntimeLlmBridge _llmBridge;
  final FrbProfileCompletionTraceRecorder? _recordTrace;

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final startedAt = DateTime.now().toUtc();
    final agentId = _metadataString(metadata, 'agent_id') ?? 'knowledge_llm';
    final surface = _metadataString(metadata, 'surface') ?? agentId;
    try {
      final response = await _llmBridge.completeProfile(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
      );
      await _recordTrace?.call(
        agentId: agentId,
        llmResponse: response,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: 'knowledge',
        surface: surface,
      );
      return response;
    } on Object catch (error) {
      await _recordTrace?.call(
        agentId: agentId,
        llmResponse: null,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: 'knowledge',
        surface: surface,
        error: error,
      );
      rethrow;
    }
  }
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

class FrbIngestLlmProfileClient implements IngestLlmProfileClient {
  const FrbIngestLlmProfileClient({
    required AgentRuntimeLlmBridge llmBridge,
    FrbProfileCompletionTraceRecorder? recordTrace,
  }) : _llmBridge = llmBridge,
       _recordTrace = recordTrace;

  final AgentRuntimeLlmBridge _llmBridge;
  final FrbProfileCompletionTraceRecorder? _recordTrace;

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final startedAt = DateTime.now().toUtc();
    final agentId = _metadataString(metadata, 'agent_id') ?? 'finance_ingest';
    final surface = _metadataString(metadata, 'surface') ?? agentId;
    try {
      final response = await _llmBridge.completeProfile(
        messages: messages,
        tools: tools,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
      );
      await _recordTrace?.call(
        agentId: agentId,
        llmResponse: response,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: 'finance',
        surface: surface,
        routingReason: kFrbVisionIngestRoutingReason,
      );
      return response;
    } on Object catch (error) {
      await _recordTrace?.call(
        agentId: agentId,
        llmResponse: null,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        domain: 'finance',
        surface: surface,
        routingReason: kFrbVisionIngestRoutingReason,
        error: error,
      );
      rethrow;
    }
  }
}

/// Kick off Memory Runtime maintenance without blocking first paint.
///
/// Real EmbeddingGemma startup includes FRB init + ONNX session warm-up,
/// which can take long enough to look like a black screen if awaited
/// before `runApp()`. These jobs are startup hygiene only; callers that
/// need memory later still await [memoryRuntimeProvider] normally.
void _scheduleMemoryRuntimeStartupTasks({
  required ProviderContainer container,
  required AppLogger logger,
}) {
  // If the embedder changed
  // since last run (e.g. swapping Stub ↔ Rust EmbeddingGemma), invalidate
  // any memory_embeddings produced by a different fingerprint so the next
  // indexer cycle re-embeds with the current model.
  unawaited(() async {
    try {
      final runtime = await container.read(
        memory_providers.memoryRuntimeProvider.future,
      );
      final dropped = await runtime.dropStaleVectors();
      if (dropped > 0) {
        logger.i('Memory Runtime dropped $dropped stale embeddings on boot');
      }
    } on Object catch (e, st) {
      logger.w(
        'Memory Runtime stale-vector sweep failed',
        error: e,
        stackTrace: st,
      );
    }
  }());
}

/// Construct the Rust EmbeddingGemma embedder, or log + fall back to
/// [StubEmbedder]. Async because `RustGemmaEmbedder.load` is
/// (FRB init + ONNX warm-up); centralised so the embedder override
/// stays a single-expression in the Riverpod overrides list.
Future<Embedder> _loadRustEmbedderOrFallback({
  required String modelDir,
  required String ortDylibPath,
  required String? libraryPath,
  required AppLogger logger,
}) async {
  final started = Stopwatch()..start();
  logger.i(
    'Rust embedder loading started '
    '(modelDir=$modelDir, ortDylibPath=$ortDylibPath, '
    'libraryPath=${libraryPath ?? '<plugin-loader>'})',
  );
  try {
    final embedder = await RustGemmaEmbedder.load(
      modelDir: modelDir,
      ortDylibPath: ortDylibPath,
      libraryPath: libraryPath,
    ).timeout(const Duration(seconds: 90));
    logger.i(
      'Rust embedder loaded (${embedder.fingerprint}, '
      'dim=${embedder.dimension}, elapsed=${started.elapsed})',
    );
    return embedder;
  } on TimeoutException catch (e, st) {
    logger.w(
      'Rust embedder load timed out; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: e,
      stackTrace: st,
    );
    return StubEmbedder();
  } on RustEmbedderUnavailable catch (e, st) {
    logger.w(
      'Rust embedder unavailable; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: e,
      stackTrace: st,
    );
    return StubEmbedder();
  } on Object catch (e, st) {
    logger.w(
      'Rust embedder load failed unexpectedly; falling back to StubEmbedder '
      '(elapsed=${started.elapsed})',
      error: e,
      stackTrace: st,
    );
    return StubEmbedder();
  }
}

/// Flutter can occasionally receive a duplicate platform KeyDown without an
/// intervening KeyUp, most often around OS/browser shortcuts or focus changes.
/// The framework asserts before app-level Shortcuts/Focus handlers run, so the
/// app cannot prevent the event. Treat that specific debug assertion as
/// non-fatal while leaving all other framework errors on the normal crash path.
@visibleForTesting
bool isBenignDuplicateKeyDownAssertion(FlutterErrorDetails details) {
  final text = details.exception.toString();
  return text.contains('hardware_keyboard.dart') &&
      text.contains('A KeyDownEvent is dispatched') &&
      text.contains('physical key is already pressed');
}

/// Runs [body] inside a guarded zone so async errors bubble to [AppLogger].
/// Use this from `main()` to wrap `runApp(...)`.
Future<void> runGuarded(Future<void> Function() body) async {
  await runZonedGuarded(body, (error, stack) {
    AppLogger.instance.e(
      'Uncaught zone error',
      error: error,
      stackTrace: stack,
    );
  });
}
