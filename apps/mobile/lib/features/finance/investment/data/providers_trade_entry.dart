part of 'providers.dart';

final _tradeCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  return FxRateCurrencyConverter(ref.watch(currentFxLookupProvider));
});

/// Deadline for dependency resolution and optional market-price backfill
/// before a trade opens its durable database transaction.
final tradeEntryPreflightTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 12),
);

/// Independent budget for constructing the repository graph. Kept separate
/// from market/preflight overrides so a short quote timeout cannot make local
/// repository initialization flaky under load.
final tradeEntryDependencyTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 12),
);

final tradeEntryServiceProvider = FutureProvider<TradeEntryService>((
  ref,
) async {
  final fx = ref.watch(_tradeCurrencyConverterProvider);
  return DefaultTradeEntryService(
    marketLoader: () => ref.read(marketDataServiceProvider.future),
    marketLookupTimeout: ref.watch(tradeEntryPreflightTimeoutProvider),
    fx: fx,
  );
});

final tradeEntrySubmissionServiceProvider =
    FutureProvider<TradeEntrySubmissionService>((ref) async {
      final logger = ref.read(loggerProvider);
      final operation = logger.startOperation('finance.trade.dependencies');
      final configuredTimeout = ref.watch(tradeEntryDependencyTimeoutProvider);
      final dependencyBudget = Duration(
        milliseconds: configuredTimeout.inMilliseconds <= 1
            ? 1
            : configuredTimeout.inMilliseconds * 9 ~/ 10,
      );
      final stopwatch = Stopwatch()..start();

      Future<T> resolve<T>(String stage, Future<T> Function() action) {
        final remaining = dependencyBudget - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          return Future<T>.error(
            TimeoutException('Trade dependency budget exhausted.'),
          );
        }
        return operation.step(
          stage,
          () => action().timeout(remaining),
          slowThreshold: const Duration(seconds: 1),
        );
      }

      try {
        final db = await resolve(
          'resolve_database',
          () => ref.watch(appDatabaseProvider.future),
        );
        final securitiesRepo = await resolve(
          'resolve_securities_repository',
          () => ref.watch(securitiesAssetRepositoryProvider.future),
        );
        final tradeService = await resolve(
          'resolve_trade_service',
          () => ref.watch(tradeEntryServiceProvider.future),
        );
        final journalEntryRepo = await resolve(
          'resolve_journal_repository',
          () => ref.watch(journalEntryRepositoryProvider.future),
        );
        final priceRepo = await resolve(
          'resolve_price_repository',
          () => ref.watch(priceRepositoryProvider.future),
        );
        final result = TradeEntrySubmissionService(
          db: db,
          securitiesRepo: securitiesRepo,
          tradeService: tradeService,
          journalEntryRepo: journalEntryRepo,
          priceRepo: priceRepo,
          currentUserId: ref.watch(currentUserIdProvider),
        );
        operation.complete();
        return result;
      } catch (error, stackTrace) {
        operation.fail(
          error,
          stackTrace: stackTrace,
          stage: 'resolve_dependencies',
          retryable: true,
          level: AppLogLevel.warning,
        );
        rethrow;
      } finally {
        stopwatch.stop();
      }
    }, retry: (_, _) => null);
