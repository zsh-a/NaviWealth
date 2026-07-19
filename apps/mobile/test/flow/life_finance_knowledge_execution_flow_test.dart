import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  testWidgets(
    'Task: Finance evidence becomes an Execution action with a visible outcome',
    (tester) async {
      await _runLoop(
        tester,
        enabledDomains: const <DomainScope>[DomainScope.execution],
        signalOverrides: <Override>[
          activityFeedProvider.overrideWith(
            (_) => Stream<ActivityFeedPage>.value(_financeFeed()),
          ),
        ],
        signalTitle: '3 finance entries today',
        evidence: '2 expenses · 1 income',
        actionTitle: "View today's finance activity",
        outcome: 'Finance: signal still detected',
      );
    },
    tags: 'flow',
  );

  testWidgets(
    'Task: Knowledge evidence becomes an Execution action with a visible outcome',
    (tester) async {
      await _runLoop(
        tester,
        enabledDomains: const <DomainScope>[
          DomainScope.knowledge,
          DomainScope.execution,
        ],
        signalOverrides: <Override>[
          knowledgeInboxNotesProvider.overrideWith(
            (_) => Stream<List<KnowledgeNote>>.value(_knowledgeNotes()),
          ),
        ],
        signalTitle: '4 notes in inbox',
        evidence: 'Notes are waiting to be organized or reviewed',
        actionTitle: 'Review the Knowledge inbox',
        outcome: 'Knowledge: signal still detected',
      );
    },
    tags: 'flow',
  );
}

Future<void> _runLoop(
  WidgetTester tester, {
  required List<DomainScope> enabledDomains,
  required List<Override> signalOverrides,
  required String signalTitle,
  required String evidence,
  required String actionTitle,
  required String outcome,
}) async {
  final data = await FlowDataHarness.create();
  addTearDown(data.dispose);
  await data.enableDomains(enabledDomains);
  await bootApp(
    tester,
    liveData: data,
    initialLocation: '/life',
    extraOverrides: signalOverrides,
  );

  final life = LifePageObject(tester);
  await life.openSignal(signalTitle);
  life.expectEvidence(evidence);
  await life.createAction(actionTitle);
  final debugActions = await ExecutionRepository(
    db: data.db,
    outbox: data.outbox,
  ).listOpenActions(ownerUserId: kLocalOnlyUserId);
  expect(
    debugActions.map((action) => action.title),
    contains(actionTitle),
    reason: 'confirmed Life proposal did not reach ExecutionRepository',
  );
  await life.openExecution();

  final execution = ExecutionTodayPageObject(tester);
  await execution.completeAction(actionTitle);
  await AppShell(tester).openTab('Review');
  final review = ExecutionReviewPageObject(tester);
  review.expectCompletedAction(actionTitle);
  review.expectOutcome(outcome);
  await closeApp(tester);
}

ActivityFeedPage _financeFeed() {
  final now = DateTime.now();
  final accounts = <String, Account>{
    'expense': _account('expense', AccountSide.expense),
    'income': _account('income', AccountSide.income),
  };
  return ActivityFeedPage(
    entries: <JournalEntryWithPostings>[
      _entry('expense-1', now, 'expense'),
      _entry('expense-2', now, 'expense'),
      _entry('income-1', now, 'income'),
    ],
    totalCount: 3,
    hasMore: false,
    isFiltered: false,
    accountsById: accounts,
  );
}

Account _account(String id, AccountSide side) => Account(
  id: id,
  type: AccountCategory.cash,
  name: id,
  currency: 'CNY',
  category: side,
  sync: _sync,
);

JournalEntryWithPostings _entry(String id, DateTime date, String accountId) =>
    JournalEntryWithPostings(
      entry: JournalEntry(id: id, date: date, narration: id, sync: _sync),
      postings: <Posting>[
        Posting(
          id: 'posting-$id',
          journalEntryId: id,
          position: 0,
          accountId: accountId,
          units: Decimal.one,
          unit: 'CNY',
          sync: _sync,
        ),
      ],
    );

List<KnowledgeNote> _knowledgeNotes() => List<KnowledgeNote>.generate(
  4,
  (index) => KnowledgeNote(
    id: 'note-$index',
    title: 'Inbox note $index',
    bodyMd: 'Review evidence $index',
    tags: const <String>[],
    createdAt: DateTime.utc(2026, 7, 17),
    sync: _sync,
  ),
);

final _sync = SyncMeta(
  ownerUserId: 'flow-user',
  updatedAt: DateTime.utc(2026, 7, 17),
  updatedByDevice: 'flow-device',
  hlc: Hlc.zero('flow-device'),
);
