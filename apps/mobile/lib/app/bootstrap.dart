import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../core/notifications/providers.dart' as notif_providers;
import '../core/perf/providers.dart';
import '../core/sync/providers.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../features/auth/data/auth_controller.dart';
import '../features/auth/data/auth_route_guard.dart';
import '../features/cashflow/data/recurring_transaction_providers.dart';
import '../features/finance/composition/finance_bootstrap.dart';
import '../features/finance/data/market/sync/price_sync_providers.dart';
import '../features/health/agents/briefing_synthesizer.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/agents/providers.dart' as health_agent_providers;
import '../features/health/data/morning_briefing_preferences.dart';
import '../features/knowledge/composition/knowledge_bootstrap.dart';
import 'domain_composition.dart';
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

  // D-1.7c: resolve embedder asset paths before the container is built
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
      // `roadmap-next.md` §3.6 — in debug builds, route captureError /
      // recordBreadcrumb through TalkerScreen via [LoggingCrashReporter]
      // so engineers see the opt-in pipeline fire end-to-end without
      // taking on the `sentry_flutter` dependency. Release builds keep
      // the [NoopCrashReporter] default until the Sentry SDK lands; the
      // opt-in gate (`crashReportingEnabledProvider`) still wraps both.
      if (kDebugMode)
        crashReporterDelegateProvider.overrideWith(
          (ref) => LoggingCrashReporter(talker: ref.watch(talkerProvider)),
        ),
      // Plug the AuthRouteGuard into FIR-15's empty default. The guard
      // reads `authControllerProvider` per redirect; auth state changes
      // bump `routeRedirectVersionProvider` which makes go_router re-run
      // the full redirect chain. Skipped when `bypassAuth` is on so dev
      // builds can browse the app without a session.
      if (!effectiveConfig.bypassAuth)
        routeGuardsProvider.overrideWith(
          (ref) => <RouteGuard>[ref.watch(authRouteGuardProvider)],
        ),
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
      core_auth.authOnUnauthorizedProvider.overrideWith(
        (ref) =>
            () => ref.read(authControllerProvider.notifier).refreshIfPossible(),
      ),
      // FinanceOS shell-seam bundle (`docs/lifeos-shell.md` §4): one
      // line replaces what used to be 6 inline overrides. Each
      // domain's `<domain>_bootstrap.dart` returns its own bundle;
      // bootstrap spreads them in turn.
      ...financeCompositionOverrides(),
      // KnowledgeOS shell-seam bundle (`docs/knowledgeos-domain.md` §15.6):
      // sole owner of the composite `proposalApplierProvider` + unioned
      // `proposalKindRegistryProvider` (Finance bundle intentionally no
      // longer overrides them — Riverpod 3 forbids double-override). Routes
      // `knowledge_*` proposals to the KnowledgeOS applier, rest to Finance.
      ...knowledgeCompositionOverrides(),
      // LifeOS domain inventory + active-domain aggregators
      // (`docs/lifeos-shell.md` §4): tools, prompt blocks, agents, shell
      // specs, and the registry all derive from the DomainPack list.
      ...lifeOsDomainCompositionOverrides(),
      // D-2.5b — wire the Morning Briefing with the LLM synthesizer
      // (falling back to programmatic when no device LLM is configured)
      // and the local notification service so each successful run can
      // surface a toast even when the app is backgrounded. The agent
      // itself stays composition-blind; this is the seam where the
      // shell decides "use which synthesis + which notifier".
      morningBriefingAgentProvider.overrideWith((ref) {
        final runtime = ref.watch(ai_chat_providers.deviceLlmRuntimeProvider);
        final notifier = ref.watch(notif_providers.notificationServiceProvider);
        final hourLocal = ref.watch(morningBriefingHourProvider);
        final BriefingSynthesizer synth = runtime != null
            ? LlmBriefingSynthesizer(client: runtime.client)
            : const ProgrammaticBriefingSynthesizer();
        return MorningBriefingAgent(
          synthesizer: synth,
          notifier: notifier,
          hourLocal: hourLocal,
        );
      }),
      // D-1.7c (`docs/lifeos-shell.md` §6.6): swap in the Rust
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
  container.read(syncSchedulerBootstrapProvider);
  container.read(priceSyncCoordinatorBootstrapProvider);
  _scheduleMemoryRuntimeStartupTasks(container: container, logger: logger);
  // Eager-bind Memory Layer indexers (`docs/lifeos-shell.md` §6, D-1.7).
  // Reading this provider subscribes the trade-journal indexer (and any
  // future domain indexers) to their source streams so semantic memory
  // stays current without UI involvement.
  container.read(memoryLayerBootstrapProvider);
  // D-2.5b — drive the platform background scheduler from the
  // Health domain opt-in. Eager-read so the provider mounts now
  // and reacts to subsequent toggles (workmanager register / cancel
  // happens inside the provider build, see `morningBriefingCronProvider`).
  container.read(health_agent_providers.morningBriefingCronProvider);
  // D-2.5b — when the workmanager callback fired while the app was
  // backgrounded it stamped `kMorningBriefingDueAtKey`. Kick off the
  // in-process run so the freshest summary lands in Memory + the
  // notification gets refined to the actual content.
  unawaited(
    container.read(health_agent_providers.pendingBriefingRunProvider.future),
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
  // D-1.7c (`docs/lifeos-shell.md` §6.6): if the embedder changed
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
