import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/shell/sync_attention.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  SyncStatusEvent event(SyncStatus status, {int? pending}) => SyncStatusEvent(
    status: status,
    at: DateTime.utc(2026),
    outboxDepth: pending,
  );

  test('only actionable sync failures need a persistent entry', () {
    expect(syncNeedsAttention(event(SyncStatus.failed)), isTrue);
    expect(syncNeedsAttention(event(SyncStatus.offline, pending: 3)), isTrue);
    expect(syncNeedsAttention(event(SyncStatus.offline, pending: 0)), isFalse);
    expect(syncNeedsAttention(event(SyncStatus.offline)), isFalse);
    expect(syncNeedsAttention(event(SyncStatus.online)), isFalse);
    expect(syncNeedsAttention(event(SyncStatus.syncing)), isFalse);
    expect(syncNeedsAttention(null), isFalse);
  });

  test('summary distinguishes local saves from completed synchronization', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      syncOverviewMessage(l10n, event(SyncStatus.offline, pending: 3)),
      l10n.syncLocalSavedPending(3),
    );
    expect(
      syncOverviewMessage(l10n, event(SyncStatus.online, pending: 2)),
      l10n.syncLocalSavedPending(2),
    );
    expect(
      syncOverviewMessage(l10n, event(SyncStatus.failed)),
      l10n.syncLocalSavedNeedsAttention,
    );
    expect(
      syncOverviewMessage(l10n, event(SyncStatus.online, pending: 0)),
      l10n.syncStatusHeadlineOnline,
    );
  });

  test('local-only mode does not subscribe to or warn about cloud sync', () {
    var subscribed = false;
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(const AuthLocalOnly()),
        syncStatusEventStreamProvider.overrideWith((_) {
          subscribed = true;
          return Stream.value(event(SyncStatus.failed));
        }),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(syncAttentionProvider), isNull);
    expect(subscribed, isFalse);
  });

  testWidgets('cloud failure persists until the status recovers', (
    tester,
  ) async {
    final bus = SyncStatusBus(initial: event(SyncStatus.failed));
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(
          AuthLoggedIn(
            AuthSession(
              accessToken: 'test',
              expiresAt: DateTime.utc(2030),
              userId: 'owner',
              deviceId: 'device',
            ),
          ),
        ),
        syncStatusBusProvider.overrideWithValue(bus),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(bus.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            final attention = ref.watch(syncAttentionProvider);
            return Text(
              attention?.status.name ?? 'clear',
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(syncAttentionProvider)?.status, SyncStatus.failed);
    bus.emit(event(SyncStatus.online, pending: 0));
    await tester.pumpAndSettle();
    expect(container.read(syncAttentionProvider), isNull);
  });
}
