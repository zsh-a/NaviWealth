/// Local-notification delivery for watchlist price alerts.
///
/// The watchlist used to raise alerts from a `Timer` and a `ref.listen` that
/// both lived inside the page widget, then surfaced them as an in-app toast.
/// Closing the page silently disabled every rule the user had configured, even
/// though the UI still called them "alerts".
///
/// Delivery now goes through the shared local-notification channel from a
/// session-scoped monitor, so a triggered rule reaches the user wherever they
/// are in the app. The rule set is small and device-local, so the monitor only
/// subscribes to quotes while at least one rule exists.
///
/// Rules are checked only while the app is open. There is no background price
/// evaluator; the UI states this limit wherever reminders are configured.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/agents/agent_l10n.dart';
import 'package:naviwealth/core/notifications/notification_preferences.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';

/// Android notification channel for watchlist price alerts.
const NotificationChannelSpec kWatchlistAlertNotificationChannel =
    NotificationChannelSpec(
      id: 'finance.watchlist.alerts',
      name: 'Watchlist price alerts',
      description: 'Local notifications when a watched symbol crosses a price.',
    );

const String _firedSignaturesKey = 'naviwealth.finance.watchlist.alerts.fired';

/// Keeps the ledger from growing without bound on a long-lived install.
const int _maxLedgerEntries = 128;

/// How often quotes are re-checked while the app is foregrounded and at least
/// one rule is configured.
const Duration _alertPollInterval = Duration(minutes: 15);

/// Read-only capability probe. Opening a form never requests OS permission.
final watchlistSystemRemindersProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  if (!ref.watch(notificationsEnabledProvider)) return false;
  final service = ref.watch(notificationServiceProvider);
  try {
    return await service.isAvailable() && await service.hasPermissions();
  } on Object {
    return false;
  }
});

/// One triggered rule, ready to be shown.
class WatchlistAlertEvent {
  const WatchlistAlertEvent({required this.signature, required this.message});

  /// Stable identity for a (symbol, side, threshold) triple. Re-using it
  /// replaces the previous OS notification instead of stacking duplicates.
  final String signature;

  final String message;
}

/// Alerts the OS channel could not deliver (web / desktop, permission denied).
/// The watchlist page surfaces these as in-app messages while it is visible.
typedef WatchlistAlertFallback = WatchlistAlertEvent;

final watchlistAlertMonitorProvider = Provider<WatchlistAlertMonitor>((ref) {
  final monitor = WatchlistAlertMonitor(ref);
  monitor.start();
  ref.onDispose(monitor.stop);
  return monitor;
});

/// Alerts the OS channel could not deliver, surfaced by the watchlist page as
/// in-app messages while it is on screen.
final watchlistAlertFallbacksProvider =
    StreamProvider.autoDispose<WatchlistAlertFallback>((ref) {
      final monitor = ref.watch(watchlistAlertMonitorProvider);
      // Re-evaluate undelivered reminders when an in-app presenter becomes
      // available, including after the watchlist page has been closed.
      scheduleMicrotask(monitor.refresh);
      return monitor.fallbacks;
    });

/// Session-scoped evaluator for [PriceAlertRules].
///
/// Started once by Finance's background bootstrap. It owns three decisions:
/// whether any rule exists at all, when quotes are refreshed, and how a
/// triggered rule reaches the user.
class WatchlistAlertMonitor with WidgetsBindingObserver {
  WatchlistAlertMonitor(this._ref);

  final Ref _ref;
  final _fallbacks = StreamController<WatchlistAlertFallback>.broadcast();

  ProviderSubscription<Object?>? _itemsSubscription;
  ProviderSubscription<Object?>? _quotesSubscription;
  Timer? _pollTimer;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  final Set<String> _inFlight = {};

  /// Delivered rule signatures. Kept in memory so two quote emissions in the
  /// same tick cannot double-fire while the persisted ledger catches up.
  Set<String>? _fired;

  /// In-app fallback events, for platforms without a local-notification
  /// runtime and for users who denied the OS permission.
  Stream<WatchlistAlertFallback> get fallbacks => _fallbacks.stream;

  /// Idempotent. Safe to call from bootstrap.
  void start() {
    if (_started) return;
    _started = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _itemsSubscription = _ref.listen<AsyncValue<List<WatchlistItem>>>(
      watchlistItemsProvider,
      (_, next) => next.whenData(_onItems),
      fireImmediately: true,
    );
  }

  void stop() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _itemsSubscription?.close();
    _itemsSubscription = null;
    _stopWatchingQuotes();
    unawaited(_fallbacks.close());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final wasBackgrounded = !_foreground;
        _foreground = true;
        if (wasBackgrounded && _quotesSubscription != null) {
          refresh();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
    }
  }

  /// Runs one evaluation pass against [snapshots]. Exposed for tests so rule
  /// matching and de-duplication can be verified without a widget tree.
  Future<List<WatchlistAlertEvent>> dispatch(
    List<WatchlistQuoteSnapshot> snapshots,
  ) async {
    if (_disposed || !_foreground) return const [];
    final l10n = _l10n();
    final fired = _fired ??= _ledger.read();
    final events = evaluateWatchlistAlerts(
      snapshots: snapshots,
      l10n: l10n,
      alreadyFired: {...fired, ..._inFlight},
    );
    if (events.isEmpty) return events;
    _inFlight.addAll(events.map((event) => event.signature));
    try {
      final canNotify = await _canNotify();
      for (final event in events) {
        if (_disposed || !_foreground) break;
        if (canNotify) {
          try {
            await _ref
                .read(notificationServiceProvider)
                .showNow(
                  id: watchlistAlertNotificationId(event.signature),
                  title: l10n.watchlistTitle,
                  body: event.message,
                  channel: kWatchlistAlertNotificationChannel,
                  payload: FinanceRoutes.wealthWatchlist,
                );
            await acknowledge(event);
            continue;
          } on Object {
            // An undelivered reminder stays eligible for the in-app path.
          }
        }
        if (!_disposed && _foreground && _fallbacks.hasListener) {
          _fallbacks.add(event);
        }
      }
    } finally {
      _inFlight.removeAll(events.map((event) => event.signature));
    }
    return events;
  }

  /// Called only after the OS or a visible in-app presenter accepted delivery.
  Future<void> acknowledge(WatchlistAlertEvent event) async {
    if (_disposed) return;
    (_fired ??= _ledger.read()).add(event.signature);
    await _ledger.remember({event.signature});
  }

  void refresh() {
    if (!_disposed && _foreground && _quotesSubscription != null) {
      _ref.invalidate(watchlistSymbolQuoteProvider);
      _ref.invalidate(watchlistQuoteUpdatesProvider);
      _ref.invalidate(watchlistQuoteSnapshotsProvider);
    }
  }

  /// `true` only when the OS channel can actually receive a notification.
  /// Every probe is defensive: a platform without a notification runtime must
  /// degrade to the in-app message instead of failing the evaluation pass.
  Future<bool> _canNotify() async {
    try {
      if (!_ref.read(notificationsEnabledProvider)) return false;
      final notifications = _ref.read(notificationServiceProvider);
      return await notifications.isAvailable() &&
          await notifications.hasPermissions();
    } on Object {
      return false;
    }
  }

  void _onItems(List<WatchlistItem> items) {
    final hasRules = items.any(
      (item) => item.alertRules.enabled && item.alertRules.hasRule,
    );
    if (!hasRules) {
      _stopWatchingQuotes();
      return;
    }
    if (_quotesSubscription != null) return;
    _quotesSubscription = _ref.listen<AsyncValue<List<WatchlistQuoteSnapshot>>>(
      watchlistQuoteUpdatesProvider(const WatchlistScope.all()),
      (_, next) => next.whenData((snapshots) => unawaited(dispatch(snapshots))),
      fireImmediately: true,
    );
    _pollTimer = Timer.periodic(_alertPollInterval, (_) {
      refresh();
    });
  }

  void _stopWatchingQuotes() {
    _quotesSubscription?.close();
    _quotesSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  WatchlistAlertLedger get _ledger =>
      WatchlistAlertLedger(_ref.read(sharedPreferencesProvider));

  AppLocalizations _l10n() => agentL10n(_ref);
}

/// Matches every configured rule against the latest quotes.
///
/// Pure so the matching rules are testable and identical in every delivery
/// path. `alreadyFired` filters out rules that have already been delivered.
List<WatchlistAlertEvent> evaluateWatchlistAlerts({
  required Iterable<WatchlistQuoteSnapshot> snapshots,
  required AppLocalizations l10n,
  required Set<String> alreadyFired,
  DateTime? now,
}) {
  final checkedAt = now ?? DateTime.now().toUtc();
  final events = <WatchlistAlertEvent>[];
  for (final snapshot in snapshots) {
    final quote = snapshot.quote;
    final rules = snapshot.item.alertRules;
    if (quote == null ||
        snapshot.hasError ||
        snapshot.response?.freshness == DataFreshness.stale ||
        quote.asOf.isAfter(checkedAt) ||
        quote.symbol.toUpperCase() != snapshot.item.displaySymbol ||
        !rules.enabled ||
        !rules.hasRule) {
      continue;
    }
    final symbol = snapshot.item.displaySymbol;

    final above = rules.above;
    if (above != null && quote.price >= above) {
      _add(
        events,
        alreadyFired,
        signature: _ruleSignature(snapshot.item, 'above', '$above'),
        message: l10n.watchlistAlertTriggeredAbove(symbol, '${quote.price}'),
      );
    }
    final below = rules.below;
    if (below != null && quote.price <= below) {
      _add(
        events,
        alreadyFired,
        signature: _ruleSignature(snapshot.item, 'below', '$below'),
        message: l10n.watchlistAlertTriggeredBelow(symbol, '${quote.price}'),
      );
    }
  }
  return events;
}

String _ruleSignature(WatchlistItem item, String side, String threshold) =>
    jsonEncode([
      item.sync.ownerUserId,
      item.id,
      item.sync.hlc.toString(),
      side,
      threshold,
    ]);

void _add(
  List<WatchlistAlertEvent> events,
  Set<String> alreadyFired, {
  required String signature,
  required String message,
}) {
  if (alreadyFired.contains(signature)) return;
  events.add(WatchlistAlertEvent(signature: signature, message: message));
}

/// Remembers which rules already reached the user so a restart (or a second
/// device refresh) does not re-announce the same crossing.
class WatchlistAlertLedger {
  const WatchlistAlertLedger(this._preferences);

  final SharedPreferences _preferences;

  Set<String> read() =>
      (_preferences.getStringList(_firedSignaturesKey) ?? const <String>[])
          .toSet();

  Future<void> remember(Set<String> signatures) async {
    final next = read()..addAll(signatures);
    final trimmed = next.length <= _maxLedgerEntries
        ? next
        : next
              .toList(growable: false)
              .sublist(next.length - _maxLedgerEntries)
              .toSet();
    await _preferences.setStringList(
      _firedSignaturesKey,
      trimmed.toList(growable: false),
    );
  }

  Future<void> clear() => _preferences.remove(_firedSignaturesKey);
}

/// Deterministic notification id derived from a rule signature, so a repeat
/// delivery replaces the previous entry instead of stacking a second one.
int watchlistAlertNotificationId(String signature) {
  var hash = 0x811c9dc5;
  for (final unit in signature.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
