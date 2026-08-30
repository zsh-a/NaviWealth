import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_rewrite_client.dart';

void main() {
  const noteRequest = KnowledgeRewriteRequest(
    kind: KnowledgeRewriteKind.note,
    style: KnowledgeRewriteStyle.clear,
    objectId: 'note-1',
    locale: 'en',
    heading: '  Rough title  ',
    content: 'Keep 12 months and https://example.com.',
  );

  test('prompt treats source text as data and preserves factual anchors', () {
    final system = knowledgeRewriteSystemPrompt(noteRequest);
    final payload = jsonDecode(knowledgeRewriteUserPrompt(noteRequest)) as Map;

    expect(system, contains('untrusted source text'));
    expect(system, contains('Do not add facts'));
    expect(system, contains('GitHub-Flavored Markdown'));
    expect(system, contains('fenced code blocks verbatim'));
    expect(system, contains('must be JSON-escaped'));
    expect(system, contains('empty title'));
    expect(payload['kind'], 'note');
    expect(payload['style'], 'clear');
    expect(
      (payload['source'] as Map)['body'],
      'Keep 12 months and https://example.com.',
    );
  });

  test('parses a fenced note JSON response', () {
    final draft = parseKnowledgeRewriteDraft(
      kind: KnowledgeRewriteKind.note,
      response: '''```json
{"title":"Clear title","body":"Clear body"}
```''',
    );

    expect(draft.heading, 'Clear title');
    expect(draft.content, 'Clear body');
  });

  test('parses decision question and rationale', () {
    final draft = parseKnowledgeRewriteDraft(
      kind: KnowledgeRewriteKind.decision,
      response: '{"question":"Choose A?","rationale":"Because B."}',
    );

    expect(draft.heading, 'Choose A?');
    expect(draft.content, 'Because B.');
  });

  test('rejects missing or empty rewrite fields', () {
    expect(
      () => parseKnowledgeRewriteDraft(
        kind: KnowledgeRewriteKind.note,
        response: '{"title":"Only title"}',
      ),
      throwsFormatException,
    );
    expect(
      () => parseKnowledgeRewriteDraft(
        kind: KnowledgeRewriteKind.note,
        response: '{"title":" ","body":" "}',
      ),
      throwsFormatException,
    );
    expect(
      () => parseKnowledgeRewriteDraft(
        kind: KnowledgeRewriteKind.note,
        response: '{"title":"Title","body":"Body","extra":true}',
      ),
      throwsFormatException,
    );
    expect(
      () => parseKnowledgeRewriteDraft(
        kind: KnowledgeRewriteKind.note,
        response: 'Here is the result: {"title":"Title","body":"Body"}',
      ),
      throwsFormatException,
    );
  });

  test('validates empty fields and factual anchors', () {
    expect(
      validateKnowledgeRewriteDraft(
        request: noteRequest,
        draft: const KnowledgeRewriteDraft(
          heading: 'Clear title',
          content: 'Keep 12 months and https://example.com.',
        ),
      ).content,
      contains('12 months'),
    );
    expect(
      () => validateKnowledgeRewriteDraft(
        request: noteRequest,
        draft: const KnowledgeRewriteDraft(
          heading: 'Clear title',
          content: 'Keep a year.',
        ),
      ),
      throwsFormatException,
    );
    expect(
      validateKnowledgeRewriteDraft(
        request: const KnowledgeRewriteRequest(
          kind: KnowledgeRewriteKind.note,
          style: KnowledgeRewriteStyle.clear,
          objectId: 'note-2',
          locale: 'en',
          heading: '',
          content: 'Body',
        ),
        draft: const KnowledgeRewriteDraft(
          heading: 'Derived title',
          content: 'Body',
        ),
      ).heading,
      'Derived title',
    );
    expect(
      () => validateKnowledgeRewriteDraft(
        request: const KnowledgeRewriteRequest(
          kind: KnowledgeRewriteKind.decision,
          style: KnowledgeRewriteStyle.clear,
          objectId: 'decision-2',
          locale: 'en',
          heading: '',
          content: 'Rationale',
        ),
        draft: const KnowledgeRewriteDraft(
          heading: 'Invented question?',
          content: 'Rationale',
        ),
      ),
      throwsFormatException,
    );
  });

  test('normalizes thousands separators when validating numbers', () {
    final draft = validateKnowledgeRewriteDraft(
      request: const KnowledgeRewriteRequest(
        kind: KnowledgeRewriteKind.decision,
        style: KnowledgeRewriteStyle.concise,
        objectId: 'decision-1',
        locale: 'en',
        heading: 'Invest 12,000?',
        content: 'Limit exposure to 25%.',
      ),
      draft: const KnowledgeRewriteDraft(
        heading: 'Invest 12000?',
        content: 'Cap exposure at 25%.',
      ),
    );

    expect(draft.heading, 'Invest 12000?');
  });

  test('preserves Markdown link targets and fenced code blocks', () {
    const request = KnowledgeRewriteRequest(
      kind: KnowledgeRewriteKind.note,
      style: KnowledgeRewriteStyle.structured,
      objectId: 'note-md',
      locale: 'en',
      heading: 'Build notes',
      content: '''Read [the guide](docs/guide.md).

```dart
final answer = 42;
```''',
    );
    const valid = KnowledgeRewriteDraft(
      heading: 'Build notes',
      content: '''## Next step

Read [the guide](docs/guide.md).

```dart
final answer = 42;
```''',
    );

    expect(
      validateKnowledgeRewriteDraft(request: request, draft: valid),
      same(valid),
    );
    expect(
      () => validateKnowledgeRewriteDraft(
        request: request,
        draft: const KnowledgeRewriteDraft(
          heading: 'Build notes',
          content: 'Read the guide. The answer is 42.',
        ),
      ),
      throwsFormatException,
    );
  });
}
