import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/ai_chat/application/batch_proposal_apply_coordinator.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/proposals/propose_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

ReadyProposalPlan _child(int index) => ReadyProposalPlan(
  proposalId: 'child-$index',
  kind: 'expense',
  summaryZh: 'Child $index',
  payload: const <String, Object?>{},
);

BatchProposalPlan _plan() => BatchProposalPlan(
  proposalId: 'batch-1',
  kind: 'batch',
  summaryZh: 'Monthly cleanup',
  children: [_child(0), _child(1), _child(2)],
);

ProposalApplyState _childState(int index) => ProposalApplyState(
  status: ProposalApplyStatus.applied,
  appliedEntityId: 'entry-$index',
  appliedTable: 'journal_entries',
);

Widget _wrap(ProposalApplyState state) {
  final invocation = ToolInvocation(
    id: 'tool-1',
    name: 'propose_batch',
    input: const <String, Object?>{},
    applyState: state,
  );
  final message = ChatMessage(
    id: 'message-1',
    sessionId: 'session-1',
    ownerUserId: 'user-1',
    role: ChatRole.assistant,
    content: '',
    status: ChatMessageStatus.complete,
    createdAt: DateTime.utc(2026, 1, 1),
    toolCalls: [invocation],
  );
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ProposeCard(
          sessionId: 'session-1',
          message: message,
          invocation: invocation,
          plan: _plan(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows child-level applying progress', (tester) async {
    final state = ProposalApplyState(
      status: ProposalApplyStatus.applying,
      undoData: BatchProposalProgress(
        completed: 1,
        total: 3,
        remainingChildren: [_childState(0)],
      ).toJson(),
    );

    await tester.pumpWidget(_wrap(state));
    await tester.pump();

    expect(find.text('Applying 1 of 3'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Recording…'), findsOneWidget);
    expect(find.text('Undo applied items'), findsNothing);
    expect(
      find.textContaining('still needs to be undone before retrying'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial rollback debt replaces retry with recovery action', (
    tester,
  ) async {
    final state = ProposalApplyState(
      status: ProposalApplyStatus.errored,
      errorMessage: 'Child failed',
      undoData: BatchProposalProgress(
        completed: 1,
        total: 3,
        failedIndex: 1,
        remainingChildren: [_childState(0)],
      ).toJson(),
    );

    await tester.pumpWidget(_wrap(state));
    await tester.pump();

    expect(find.text('Undo applied items'), findsOneWidget);
    expect(
      find.textContaining('still needs to be undone before retrying'),
      findsOneWidget,
    );
    expect(find.text('Confirm all'), findsNothing);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Cancel')).onPress,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
