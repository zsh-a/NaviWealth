import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/providers.dart';
import '../market_data_providers.dart';
import 'fx_rate_sync_service.dart';

/// The [FxRateSyncService] instance, wired to the market data pipeline and
/// the local FX rate repository.
final fxRateSyncServiceProvider = FutureProvider<FxRateSyncService>((
  ref,
) async {
  final marketData = await ref.watch(marketDataServiceProvider.future);
  final fxRepo = await ref.watch(fxRateRepositoryProvider.future);
  return FxRateSyncService(marketData: marketData, fxRepo: fxRepo);
});
