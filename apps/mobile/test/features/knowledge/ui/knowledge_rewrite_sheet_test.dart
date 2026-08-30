import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_markdown.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_rewrite_client.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_rewrite_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('generates a preview and returns only after explicit apply', (
    tester,
  ) async {
    final client = _FakeRewriteClient();
    KnowledgeRewriteDraft? applied;
    await _pumpHost(
      tester,
      client: client,
      onResult: (value) => applied = value,
    );

    await tester.tap(find.text('Open'));
    await _settleKnowledgeRewrite(tester);
    expect(find.text('Original'), findsOneWidget);
    expect(applied, isNull);

    await tester.tap(find.byKey(const Key('knowledge-rewrite-submit')));
    await _settleKnowledgeRewrite(tester);

    expect(client.requests, hasLength(1));
    expect(client.requests.single.kind, KnowledgeRewriteKind.note);
    expect(find.text('Proposed rewrite'), findsOneWidget);
    expect(find.text('Clear title'), findsOneWidget);
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(
      tester.widget<AiMarkdown>(find.byType(AiMarkdown)).text,
      contains('**Clear**'),
    );
    expect(applied, isNull);

    await tester.tap(find.text('Edit Markdown'));
    await _settleKnowledgeRewrite(tester);
    expect(
      find.byKey(const Key('knowledge-rewrite-content-editor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('knowledge-rewrite-submit')));
    await _settleKnowledgeRewrite(tester);

    expect(applied?.heading, 'Clear title');
    expect(applied?.content, '**Clear** body');
    expect(find.text('Rewrite Knowledge'), findsNothing);
  });

  testWidgets('shows an unavailable state without a generate action', (
    tester,
  ) async {
    await _pumpHost(tester, client: null, onResult: (_) {});

    await tester.tap(find.text('Open'));
    await _settleKnowledgeRewrite(tester);

    expect(
      find.text(
        'Configure and activate an AI model provider in Settings to rewrite this item.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('knowledge-rewrite-submit')), findsNothing);
  });

  testWidgets('shows a clear message when the model returns no content', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      client: const _EmptyRewriteClient(),
      onResult: (_) {},
    );

    await tester.tap(find.text('Open'));
    await _settleKnowledgeRewrite(tester);
    await tester.tap(find.byKey(const Key('knowledge-rewrite-submit')));
    await _settleKnowledgeRewrite(tester);

    expect(
      find.text(
        'The model returned no rewrite. Try again or choose a different model.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Unexpected end of input'), findsNothing);
  });
}

Future<void> _settleKnowledgeRewrite(WidgetTester tester) async {
  // Matches the existing Knowledge capture flow workaround for Forui's
  // transient merged-semantics assertion during bottom-sheet animation.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100), EnginePhase.paint);
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required KnowledgeRewriteClient? client,
  required ValueChanged<KnowledgeRewriteDraft?> onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [knowledgeRewriteClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppMessenger.init(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    onResult(
                      await showKnowledgeRewriteSheet(
                        context: context,
                        kind: KnowledgeRewriteKind.note,
                        objectId: 'note-1',
                        heading: 'Rough title',
                        content: 'Rough body',
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FakeRewriteClient implements KnowledgeRewriteClient {
  final requests = <KnowledgeRewriteRequest>[];

  @override
  Future<KnowledgeRewriteDraft> rewrite(KnowledgeRewriteRequest request) async {
    requests.add(request);
    return const KnowledgeRewriteDraft(
      heading: 'Clear title',
      content: '**Clear** body',
    );
  }
}

class _EmptyRewriteClient implements KnowledgeRewriteClient {
  const _EmptyRewriteClient();

  @override
  Future<KnowledgeRewriteDraft> rewrite(KnowledgeRewriteRequest request) {
    throw const KnowledgeRewriteEmptyResponseException(finishReason: 'length');
  }
}
