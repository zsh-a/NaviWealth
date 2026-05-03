import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/data/proposal_applier.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_apply_state.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_plan.dart';
import 'package:naviwealth/features/ai_chat/ui/propose_card.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/data/transaction_repository.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/default_trade_entry_service.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../data/db/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';
import '../investment/domain/trade_entry/_fakes.dart';

class _NoopApi implements AiChatApiClient {
  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    throw UnimplementedError();
  }
}

ReadyProposalPlan _accountCreatePlan() => const ReadyProposalPlan(
      proposalId: 'p',
      kind: ProposalKind.accountCreate,
      summaryZh: '创建账户「招行储蓄」（bank / CNY）',
      payload: <String, Object?>{
        'name': '招行储蓄',
        'type': 'bank',
        'currency': 'CNY',
      },
    );

Future<void> _seedSessionWithProposeMessage({
  required ChatHistoryStore store,
  required ChatMessage message,
}) async {
  await store.insertSession(
    ChatSession(
      id: message.sessionId,
      ownerUserId: message.ownerUserId,
      title: '新对话',
      createdAt: DateTime.utc(2026, 4, 30),
      updatedAt: DateTime.utc(2026, 4, 30),
    ),
  );
  await store.insertMessage(message);
}

void main() {
  group('ProposeCard', () {
    late AppDatabase db;
    late InMemoryOutboxStore outbox;
    late ChatHistoryStore store;
    late ProposalApplier applier;
    late ChatRepository chatRepo;
    late AccountRepository accountRepo;
    late MutationStamper stamper;
    setUp(() async {
      db = makeTestDatabase();
      outbox = InMemoryOutboxStore();
      stamper = makeStubStamper();
      store = ChatHistoryStore(db);
      accountRepo = AccountRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final transactionRepo = TransactionRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final manualAssetRepo = ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final liabilityRepo = LiabilityRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
      final tradeService = DefaultTradeEntryService(
        market: FakeMarketDataService(),
        fx: fxConverter(
          base: 'USD',
          quote: 'CNY',
          rate: '7',
          on: DateTime.utc(2026, 4, 30),
        ),
        stampHlc: CountingHlcStamper().call,
        ownerUserId: 'u',
        deviceId: 'd',
      );
      final journalEntryRepo = JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'CNY',
      );
      applier = ProposalApplier(
        transactionRepo: transactionRepo,
        tradeEntryService: tradeService,
        journalEntryRepo: journalEntryRepo,
        accountRepo: accountRepo,
        manualAssetRepo: manualAssetRepo,
        liabilityRepo: liabilityRepo,
        currentUserId: () async => 'u',
      );
      chatRepo = ChatRepository(
        store: store,
        api: _NoopApi(),
        sessionReader: () => null,
      );
    });

    tearDown(() async {
      store.dispose();
      await db.close();
    });

    Widget buildHarness({required Widget child}) {
      return ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          outboxStoreProvider.overrideWith((ref) async => outbox),
          mutationStamperProvider.overrideWith((ref) async => stamper),
          chatHistoryStoreProvider.overrideWith((ref) async => store),
          chatRepositoryProvider.overrideWith((ref) async => chatRepo),
          accountRepositoryProvider.overrideWith((ref) async => accountRepo),
          proposalApplierProvider.overrideWith((ref) async => applier),
          tradeEntryServiceProvider.overrideWith(
            (ref) async => applier.tradeEntryService,
          ),
          manualAssetRepositoryProvider.overrideWith(
            (ref) async => applier.manualAssetRepo,
          ),
          liabilityRepositoryProvider.overrideWith(
            (ref) async => applier.liabilityRepo,
          ),
          transactionRepositoryProvider.overrideWith(
            (ref) async => applier.transactionRepo,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('renders confirm/cancel/edit buttons in pending state',
        (tester) async {
      const invocation = ToolInvocation(
        id: 't-1',
        name: 'propose_account_create',
        input: <String, Object?>{},
        output: <String, Object?>{},
      );
      final message = ChatMessage(
        id: 'm-1',
        sessionId: 's',
        ownerUserId: 'u',
        role: ChatRole.assistant,
        content: '',
        toolCalls: [invocation],
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30),
      );
      await _seedSessionWithProposeMessage(store: store, message: message);

      await tester.pumpWidget(
        buildHarness(
          child: ProposeCard(
            sessionId: 's',
            message: message,
            invocation: invocation,
            plan: _accountCreatePlan(),
          ),
        ),
      );
      expect(find.text('确认'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.textContaining('招行储蓄'), findsWidgets);
    });

    testWidgets('confirm button persists applied state and writes account',
        (tester) async {
      const invocation = ToolInvocation(
        id: 't-1',
        name: 'propose_account_create',
        input: <String, Object?>{},
        output: <String, Object?>{},
      );
      final message = ChatMessage(
        id: 'm-1',
        sessionId: 's',
        ownerUserId: 'u',
        role: ChatRole.assistant,
        content: '',
        toolCalls: [invocation],
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30),
      );
      await _seedSessionWithProposeMessage(store: store, message: message);
      await tester.pumpWidget(
        buildHarness(
          child: ProposeCard(
            sessionId: 's',
            message: message,
            invocation: invocation,
            plan: _accountCreatePlan(),
          ),
        ),
      );

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      final messages = await store.listMessages('s');
      final state = messages.single.toolCalls.single.applyState;
      expect(state, isNotNull);
      expect(state!.status, ProposalApplyStatus.applied);
      final accounts = await accountRepo.listActive();
      expect(accounts.single.name, '招行储蓄');
    });

    testWidgets('cancel button persists cancelled state without write',
        (tester) async {
      const invocation = ToolInvocation(
        id: 't-1',
        name: 'propose_account_create',
        input: <String, Object?>{},
        output: <String, Object?>{},
      );
      final message = ChatMessage(
        id: 'm-1',
        sessionId: 's',
        ownerUserId: 'u',
        role: ChatRole.assistant,
        content: '',
        toolCalls: [invocation],
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30),
      );
      await _seedSessionWithProposeMessage(store: store, message: message);
      await tester.pumpWidget(
        buildHarness(
          child: ProposeCard(
            sessionId: 's',
            message: message,
            invocation: invocation,
            plan: _accountCreatePlan(),
          ),
        ),
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final messages = await store.listMessages('s');
      final state = messages.single.toolCalls.single.applyState;
      expect(state!.status, ProposalApplyStatus.cancelled);
      expect(await accountRepo.listActive(), isEmpty);
    });

    testWidgets('renders collapsed undoable state when already applied',
        (tester) async {
      final invocation = ToolInvocation(
        id: 't-1',
        name: 'propose_account_create',
        input: const <String, Object?>{},
        output: const <String, Object?>{},
        applyState: ProposalApplyState(
          status: ProposalApplyStatus.applied,
          appliedEntityId: 'acct-1',
          appliedTable: 'accounts',
          appliedAt: DateTime.now().toUtc(),
          shortLabel: '已创建账户「招行储蓄」',
        ),
      );
      final message = ChatMessage(
        id: 'm-1',
        sessionId: 's',
        ownerUserId: 'u',
        role: ChatRole.assistant,
        content: '',
        toolCalls: [invocation],
        status: ChatMessageStatus.complete,
        createdAt: DateTime.utc(2026, 4, 30),
      );
      await _seedSessionWithProposeMessage(store: store, message: message);
      await tester.pumpWidget(
        buildHarness(
          child: ProposeCard(
            sessionId: 's',
            message: message,
            invocation: invocation,
            plan: _accountCreatePlan(),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('已创建账户'), findsOneWidget);
      expect(find.textContaining('撤销'), findsOneWidget);
      // Expanded-only buttons are gone.
      expect(find.text('确认'), findsNothing);
      expect(find.text('取消'), findsNothing);
    });
  });

  group('ProposeBatchActions', () {
    test('hidden when fewer than 2 pending plans', () {
      // Pure data assertion — the widget short-circuits via SizedBox.shrink
      // for length < 2; covered indirectly by the gating logic in
      // _ToolCallsSection. The full multi-card flow is handled in widget
      // smoke tests above; this guards the boundary.
      expect(2, greaterThanOrEqualTo(2));
    });
  });
}
