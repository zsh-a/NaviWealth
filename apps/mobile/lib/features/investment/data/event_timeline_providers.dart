import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reporting/event_timeline.dart';

/// Per-symbol upcoming corporate-action events (`docs/roadmap-next.md`
/// §3.5). The provider is the seam the holding detail "事件" tab reads,
/// and the place where a future fetcher PR will plug in
/// `data/market/providers/yfinance_corporate_actions.dart`.
///
/// Default returns an empty list — until the yfinance fetcher lands the
/// UI will render its empty state. The page is therefore safe to ship now
/// without holding for the network plumbing.
///
/// Tests override this provider directly to inject canned events.
final corporateActionEventsProvider =
    Provider.autoDispose.family<List<CorporateActionEvent>, String>(
  (ref, symbol) => const [],
);

/// Filtered timeline projection for [symbol] over the next [windowDays]
/// days. Centralises the `buildEventTimeline` call so callers don't have
/// to thread the symbol set / window themselves — the page renders the
/// raw output of this provider.
final upcomingEventsForSymbolProvider =
    Provider.autoDispose.family<List<CorporateActionEvent>, String>(
  (ref, symbol) {
    final raw = ref.watch(corporateActionEventsProvider(symbol));
    return buildEventTimeline(
      events: raw,
      watchedSymbols: <String>{symbol},
    );
  },
);
