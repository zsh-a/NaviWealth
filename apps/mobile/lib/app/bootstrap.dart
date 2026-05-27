import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai/agents/agent.dart';
import '../core/ai/agents/agent_registry.dart';
import '../core/ai/composition/ai_context_summary.dart';
import '../core/ai/composition/chat_rail_provider.dart';
import '../core/ai/composition/chat_trace_prep.dart';
import '../core/ai/composition/device_tools_provider.dart';
import '../core/ai/composition/portfolio_snapshot.dart';
import '../core/ai/composition/proposal_applier.dart';
import '../core/ai/local/embedding/embedder.dart';
import '../core/ai/local/embedding/model_install_paths.dart';
import '../core/ai/local/embedding/model_manifest.dart';
import '../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../core/ai/local/memory/providers.dart' as memory_providers;
import '../core/ai/runtime/device/tools/device_tool.dart';
import '../core/auth/domain_scope.dart';
import '../core/auth/providers.dart' as core_auth;
import '../core/config/app_config.dart';
import '../core/format/formatters.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/crash_reporter.dart';
import '../core/logging/logging_crash_reporter.dart';
import '../core/logging/providers.dart';
import '../core/notifications/providers.dart' as notif_providers;
import '../core/perf/providers.dart';
import '../core/shell/domain_shell.dart';
import '../core/sync/providers.dart';
import '../design_system/preferences/theme_preferences.dart';
import '../features/ai_chat/data/providers.dart' as ai_chat_providers;
import '../features/auth/data/auth_controller.dart';
import '../features/auth/data/auth_route_guard.dart';
import '../features/cashflow/data/recurring_transaction_providers.dart';
import '../features/finance/composition/finance_ai_context_summary_provider.dart';
import '../features/finance/composition/finance_chat_trace_preparer.dart';
import '../features/finance/composition/finance_portfolio_snapshot.dart';
import '../features/finance/composition/finance_proposal_applier.dart';
import '../features/finance/data/market/sync/price_sync_providers.dart';
import '../features/finance_ai_tools.dart';
import '../features/finance_domain_shell.dart';
import '../features/health/agents/briefing_synthesizer.dart';
import '../features/health/agents/morning_briefing_agent.dart';
import '../features/health/agents/providers.dart' as health_agent_providers;
import '../features/health/composition/health_domain_shell.dart';
import '../features/health/data/morning_briefing_preferences.dart';
import '../features/health_ai_tools.dart';
import '../features/home/composition/finance_chat_rail_provider.dart';
import '../l10n/gen/app_localizations.dart';
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
  final resolvedEmbedderPaths = await _resolveEmbedderPaths(effectiveConfig);

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
      // D-1.6 (`docs/lifeos-shell.md` §4): FinanceOS registers the
      // chat rail content selector. The chat surface in
      // `features/ai_chat/` reads only `chatRailContentSelectorProvider`
      // — it doesn't know which domains are active.
      chatRailContentSelectorProvider.overrideWith(
        (ref) => ref.watch(financeChatRailContentSelectorProvider),
      ),
      // D-1.2 (`docs/lifeos-shell.md` §7.1) + D-2.4
      // (`docs/healthos-domain.md` §4): the device tool registry is
      // composed from each active domain's tool list. Shell + Finance
      // always ship; HealthOS tools ship only when the user has opted
      // into the Health domain (`domainOptInsProvider`).
      deviceToolsProvider.overrideWith((ref) {
        final optIns = ref.watch(core_auth.domainOptInsProvider).value;
        final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
        return <DeviceTool>[
          ...kShellDeviceTools,
          ...kFinanceDeviceTools,
          if (healthEnabled) ...kHealthDeviceTools,
        ];
      }),
      // D-2.5 (`docs/lifeos-shell.md` §7.3 + `docs/healthos-domain.md`
      // §8): register agents. The Morning Briefing agent ships only
      // when Health is opted-in — it reads health events and would be
      // a no-op without them.
      agentRegistryProvider.overrideWith((ref) {
        final optIns = ref.watch(core_auth.domainOptInsProvider).value;
        final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
        return <Agent>[
          if (healthEnabled) ref.watch(morningBriefingAgentProvider),
        ];
      }),
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
      // D-1.6b (`docs/lifeos-shell.md` §4): FinanceOS supplies the
      // concrete proposal applier the chat surface dispatches confirmed
      // `propose_*` plans through. Without this override the shell
      // default no-op applier throws on every apply.
      proposalApplierProvider.overrideWith(
        (ref) => ref.watch(financeProposalApplierProvider.future),
      ),
      // D-1.6b (`docs/lifeos-shell.md` §4): FinanceOS supplies the
      // per-chat-turn ContextPack + AiTrace seed. Default (no domain
      // registered) leaves `chatTracePrepProvider` returning null, in
      // which case `ChatRepository` skips the trace seam entirely.
      chatTracePrepProvider.overrideWith(
        (ref) => ref.watch(financeChatTracePrepProvider),
      ),
      // D-1.6b (`docs/lifeos-shell.md` §4): FinanceOS supplies the AI
      // page header summary chip. Default returns the empty summary,
      // which renders as a collapsed chip.
      aiContextSummaryProvider.overrideWith(
        (ref) => ref.watch(financeAiContextSummaryProvider),
      ),
      // D-1.6b (`docs/lifeos-shell.md` §4): FinanceOS supplies the
      // portfolio snapshot the chat surface attaches to each turn.
      portfolioSnapshotReaderProvider.overrideWith(
        (ref) => ref.watch(financePortfolioSnapshotReaderProvider),
      ),
      // D-1.8 + D-2.3 (`docs/lifeos-shell.md` §3): register the
      // FinanceOS shell spec; append HealthOS when the user has opted
      // into the Health domain. The dock visibility flips on as soon
      // as a second spec lands (see `domainDockVisibleProvider`).
      activeDomainShellsProvider.overrideWith((ref) {
        // The spec depends on AppLocalizations for labels, which is
        // resolved per-render inside the shell, not at container
        // construction. We side-step by building with the default
        // (English) locale here — the active locale is re-applied
        // when the widget tree rebuilds via Riverpod's invalidation.
        final l10n = lookupAppLocalizations(const Locale('en'));
        final optIns = ref.watch(core_auth.domainOptInsProvider).value;
        final healthEnabled = optIns?.contains(DomainScope.health) ?? false;
        return <DomainShellSpec>[
          financeDomainShell(l10n),
          if (healthEnabled) healthDomainShell(l10n),
        ];
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
  if (container.read(core_auth.authSessionProvider) != null) {
    unawaited(
      container.read(
        recurringMaterialiseDueProvider(DateTime.now().toUtc()).future,
      ),
    );
  }

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

/// Resolved file paths the Rust embedder needs (D-1.7c). All three
/// can come from either dart-define override or the in-app
/// installer's directory.
class _EmbedderPathResolution {
  const _EmbedderPathResolution({
    required this.modelDir,
    required this.ortDylibPath,
    this.libraryPath,
  });
  final String modelDir;
  final String ortDylibPath;
  final String? libraryPath;

  bool get isComplete => modelDir.isNotEmpty && ortDylibPath.isNotEmpty;

  List<String> get missingInputs => [
    if (modelDir.isEmpty) 'EmbeddingGemma model dir',
    if (ortDylibPath.isEmpty) 'ONNX Runtime dylib',
  ];
}

/// Pick the active embedder paths. When not enough inputs are
/// available to construct the Rust embedder, [isComplete] is false —
/// bootstrap then leaves the stub default in place, and the user can
/// install the model bundle via Settings → AI Models.
///
/// Precedence per field:
///   1. `--dart-define` override (dev / test path)
///   2. For `modelDir`: on-disk installer artefact (`<app_support>/embedders/`)
///   3. For `ortDylibPath`: standard locations around the executable
///      (build-time bundled by `tool/build-lifeos-native.sh` / cargokit)
///
/// ORT is build-time managed (not in the in-app installer) because
/// it's a Rust crate dep, not user data; `tool/fetch-onnxruntime.sh`
/// downloads + places it alongside `liblifeos_native.{dylib,so}`.
Future<_EmbedderPathResolution> _resolveEmbedderPaths(AppConfig config) async {
  String modelDir = config.rustEmbedderModelDir;
  String ortDylibPath = config.rustEmbedderOrtDylibPath;

  if (modelDir.isEmpty) {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory(path.join(support.path, 'embedders'));
      final gemma = embeddingGemmaBundle();
      final gemmaDir = Directory(path.join(root.path, gemma.id));
      final paths = ModelInstallPaths.unsafeForDir(root);
      if (await paths.isComplete(gemma)) {
        modelDir = gemmaDir.path;
      }
    } on Object {
      // path_provider failure (rare, e.g. sandbox issues) → bail out
      // and keep the stub embedder.
      return _EmbedderPathResolution(
        modelDir: modelDir,
        ortDylibPath: ortDylibPath,
        libraryPath: config.rustEmbedderLibraryPath.isEmpty
            ? null
            : config.rustEmbedderLibraryPath,
      );
    }
  }

  if (ortDylibPath.isEmpty) {
    ortDylibPath = _discoverBundledOrtDylib() ?? '';
  }

  return _EmbedderPathResolution(
    modelDir: modelDir,
    ortDylibPath: ortDylibPath,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
  );
}

/// Look for the build-time-bundled `libonnxruntime.{dylib,so}` next
/// to (or one level above) the running executable. Returns the first
/// existing path, or `null` if none matches — caller falls back to
/// the stub embedder.
///
/// Search order is platform-conventional:
///
/// - **macOS**: `<exec>/../Frameworks/libonnxruntime.dylib` (Pod-
///   bundled location), then `<exec>/libonnxruntime.dylib`.
/// - **Linux**: `<exec>/libonnxruntime.so`.
/// - **Android**: `libonnxruntime.so` packaged in the app's native
///   library directory by Gradle; the dynamic loader resolves by name.
/// - **iOS**: not yet wired — needs a platform-specific bundling step
///   (TODO when D-2 ships HealthOS on iOS).
///
String? _discoverBundledOrtDylib() {
  if (Platform.isAndroid) return 'libonnxruntime.so';
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  final exec = Platform.resolvedExecutable;
  final execDir = File(exec).parent;
  final dylibName = Platform.isMacOS
      ? 'libonnxruntime.dylib'
      : 'libonnxruntime.so';

  final candidates = <String>[
    if (Platform.isMacOS)
      path.join(execDir.parent.path, 'Frameworks', dylibName),
    path.join(execDir.path, dylibName),
  ];
  for (final p in candidates) {
    final normalised = path.normalize(p);
    if (File(normalised).existsSync()) return normalised;
  }
  return null;
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
