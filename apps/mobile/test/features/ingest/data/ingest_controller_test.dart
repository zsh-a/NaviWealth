import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/ai_trace.dart';
import 'package:naviwealth/core/ai/contracts/privacy_mode_provider.dart';
import 'package:naviwealth/core/ai/trace/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/ingest/data/providers.dart';
import 'package:naviwealth/features/ingest/data/vision_ingest_client.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer buildContainer({
    VisionIngestClient? visionClient,
    String ownerUserId = 'owner-1',
  }) {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWithValue(ownerUserId),
        journalExpensesStreamProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        if (visionClient != null)
          visionIngestClientProvider.overrideWithValue(visionClient),
      ],
    );
  }

  Future<IngestDraftStore> readyStore(ProviderContainer container) async {
    await container.read(appDatabaseProvider.future);
    final ledgerSubscription = container.listen(
      journalExpensesStreamProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(ledgerSubscription.close);
    await container.read(journalExpensesStreamProvider.future);
    final store = container.read(ingestDraftStoreProvider);
    expect(store, isNotNull);
    return store!;
  }

  group('IngestController', () {
    test('device CSV path persists drafts for the active owner', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final store = await readyStore(container);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.csv,
              payload:
                  'date,description,amount,currency\n'
                  '2026-06-18,Luckin Coffee,-18.00,CNY\n',
              originLabel: 'statement.csv',
            ),
          );

      expect(result.isRejected, isFalse);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.ownerUserId, 'owner-1');
      expect(result.drafts.single.originLabel, 'statement.csv');
      expect(result.drafts.single.verdict, DedupVerdict.newTxn);

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(1));
      expect(persisted.single.draftId, result.drafts.single.draftId);
      expect(persisted.single.parsed.description, 'Luckin Coffee');
      expect(persisted.single.parsed.amountMinor, -1800);
    });

    test('device path dedups re-imports against pending drafts', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final store = await readyStore(container);
      const source = IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-06-18,Netflix,-68.00,CNY\n',
      );

      final first = await container
          .read(ingestControllerProvider)
          .ingest(source);
      final second = await container
          .read(ingestControllerProvider)
          .ingest(source);

      expect(first.drafts.single.verdict, DedupVerdict.newTxn);
      expect(second.drafts.single.verdict, DedupVerdict.duplicate);
      expect(
        second.drafts.single.dedupTargetEntryId,
        first.drafts.single.draftId,
      );

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(2));
      expect(
        persisted.map((draft) => draft.draftId),
        containsAll([
          first.drafts.single.draftId,
          second.drafts.single.draftId,
        ]),
      );
    });

    test('privacy gate blocks Vision before touching the client', () async {
      final vision = _RecordingVisionIngestClient(
        parsed: const <ParsedTransaction>[],
      );
      final container = buildContainer(visionClient: vision);
      addTearDown(container.dispose);
      await readyStore(container);
      await container
          .read(aiPrivacySettingsProvider.notifier)
          .setMode(AiPrivacyMode.amountsLocal);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.receiptImage,
              payload: 'base64-image',
              mime: 'image/png',
            ),
          );

      expect(result.isRejected, isTrue);
      expect(result.rejectedReason, contains('模型解析'));
      expect(result.drafts, isEmpty);
      expect(vision.calls, 0);
    });

    test('Vision path persists parsed drafts and trace metadata', () async {
      final vision = _RecordingVisionIngestClient(
        parsed: [
          ParsedTransaction(
            description: 'Taxi receipt',
            amountMinor: -4200,
            currency: 'cny',
            occurredAt: DateTime.utc(2026, 6, 18),
            confidence: 0.72,
          ),
        ],
      );
      final container = buildContainer(visionClient: vision);
      addTearDown(container.dispose);
      final store = await readyStore(container);

      final result = await container
          .read(ingestControllerProvider)
          .ingest(
            const IngestSource(
              kind: IngestSourceKind.receiptImage,
              payload: 'base64-image',
              mime: 'image/png',
              originLabel: 'receipt.png',
            ),
          );

      expect(result.isRejected, isFalse);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.traceId, isNotNull);
      expect(result.drafts.single.parsed.description, 'Taxi receipt');
      expect(result.drafts.single.parsed.currency, 'cny');
      expect(result.drafts.single.sourceKind, IngestSourceKind.receiptImage);
      expect(vision.calls, 1);
      expect(vision.lastKind, IngestSourceKind.receiptImage);
      expect(vision.lastMime, 'image/png');
      expect(vision.lastContentBase64, 'base64-image');

      final persisted = await store.listByStatus(DraftStatus.pending);
      expect(persisted, hasLength(1));
      expect(persisted.single.traceId, result.drafts.single.traceId);
      expect(persisted.single.originLabel, 'receipt.png');

      final traces = await container.read(aiTraceStoreProvider).recent();
      expect(traces, hasLength(1));
      expect(traces.single.requestId, result.drafts.single.traceId);
      expect(traces.single.backend, Backend.device);
      expect(traces.single.routingReason, kDeviceVisionDirectRoutingReason);
      expect(
        traces.single.spans.map((span) => span.name),
        contains('tool:parse_receipt_image'),
      );
    });

    test(
      'returns an actionable rejection while the database is booting',
      () async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ingestDraftStoreProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(ingestControllerProvider)
            .ingest(
              const IngestSource(
                kind: IngestSourceKind.csv,
                payload:
                    'date,description,amount,currency\n'
                    '2026-06-18,Coffee,-18.00,CNY\n',
              ),
            );

        expect(result.isRejected, isTrue);
        expect(result.rejectedReason, contains('数据库尚未就绪'));
      },
    );
  });
}

final class _RecordingVisionIngestClient implements VisionIngestClient {
  _RecordingVisionIngestClient({required this.parsed});

  final List<ParsedTransaction> parsed;

  int calls = 0;
  IngestSourceKind? lastKind;
  String? lastMime;
  String? lastContentBase64;

  @override
  Future<List<ParsedTransaction>> parse({
    required IngestSourceKind kind,
    required String mime,
    required String contentBase64,
    String? currencyHint,
  }) async {
    calls += 1;
    lastKind = kind;
    lastMime = mime;
    lastContentBase64 = contentBase64;
    return parsed;
  }
}
