import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/agents/agent_execution_page.dart';
import 'package:naviwealth/core/ai/agents/agent_execution.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/ai_chat/ui/messages/user_message_surface.dart';
import 'package:naviwealth/features/ai_chat/ui/tools/tool_invocation_inline.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../core/persistence/test_database.dart';

void main() {
  testWidgets(
    'read-only timeline reuses chat components, updates and stops without a session',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final stream = StreamController<AgentExecution?>();
      addTearDown(stream.close);
      final token = CancelToken();
      final controls = AgentExecutionControls()
        ..register('alice', 'run', token);
      final execution =
          AgentExecution(
            runId: 'run',
            agentId: 'test',
            domain: 'finance',
            title: 'Weekly review',
            instructions: 'Review available facts',
            traceId: 'trace',
            processId: agentExecutionProcessId,
            startedAt: DateTime.now().toUtc(),
            phase: 'tool',
          )..record(
            const AiSpan(
              id: 'tool:1',
              kind: AiSpanKind.tool,
              name: 'tool:get_net_worth_summary',
              startOffsetMs: 0,
              durationMs: 0,
            ),
            running: true,
          );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeUserIdProvider.overrideWithValue('alice'),
            currentUserIdProvider.overrideWithValue(() async => 'alice'),
            appDatabaseProvider.overrideWith((_) async => db),
            agentExecutionControlsProvider.overrideWithValue(controls),
            agentExecutionProvider((agentId: 'test', runId: 'run'))
                .overrideWith((_) => stream.stream),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const AgentExecutionPage(agentId: 'test', runId: 'run'),
            ),
          ),
        ),
      );
      await tester.pump();
      stream.add(AgentExecution.fromJson(execution.toJson()));
      await tester.pump();
      await tester.pump();
      expect(find.byType(UserMessageSurface), findsOneWidget);
      expect(find.byType(ToolInvocationInline), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is EditableText && !w.readOnly),
        findsNothing,
      );
      expect(find.textContaining('Reading data'), findsOneWidget);
      await tester.tap(find.text('Stop execution'));
      await tester.pump();
      expect(token.cancelError?.error, 'scheduled_task_user_cancelled');
      execution.status = 'completed';
      execution.summary = 'Evidence-based report';
      execution.record(
        const AiSpan(
          id: 'tool:1',
          kind: AiSpanKind.tool,
          name: 'tool:get_net_worth_summary',
          startOffsetMs: 0,
          durationMs: 150,
        ),
      );
      stream.add(AgentExecution.fromJson(execution.toJson()));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AiMarkdown), findsOneWidget);
      expect(find.text('Stop execution'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets(
    'historical failure displays safe explanation without raw Bad state',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final execution = AgentExecution(
        runId: 'run',
        agentId: 'test',
        domain: 'finance',
        title: 'Review',
        instructions: 'Review facts',
        traceId: 'trace',
        processId: agentExecutionProcessId,
        startedAt: DateTime.now().toUtc(),
        status: 'failed',
        errorCode: 'invalid_report',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeUserIdProvider.overrideWithValue('alice'),
            appDatabaseProvider.overrideWith((_) async => db),
            agentExecutionProvider((agentId: 'test', runId: 'run'))
                .overrideWith((_) => Stream.value(execution)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const AgentExecutionPage(agentId: 'test', runId: 'run'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The model did not return a valid evidence-based report.'),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
