import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/ui/decision_request.dart';

void main() {
  group('DecisionRequest.tryParse', () {
    test('parses a well-formed ask_user decision_request', () {
      final req = DecisionRequest.tryParse(<String, Object?>{
        'type': 'decision_request',
        'title': '状态管理方案选择',
        'context': '本地优先 + 可同步 + AI 可读写。',
        'options': [
          {
            'id': 'riverpod',
            'label': 'Riverpod + Drift',
            'description': 'UI 用 Riverpod，持久化用 Drift。',
            'pros': ['清晰分层', '适合离线优先'],
            'cons': ['需要设计同步层'],
            'recommended': true,
          },
          {
            'id': 'bloc',
            'label': 'BLoC + Repository',
            'pros': ['可测试性强'],
          },
        ],
        'allow_custom': true,
      });
      expect(req, isNotNull);
      expect(req!.title, '状态管理方案选择');
      expect(req.allowCustom, isTrue);
      expect(req.options, hasLength(2));
      final first = req.options.first;
      expect(first.id, 'riverpod');
      expect(first.label, 'Riverpod + Drift');
      expect(first.recommended, isTrue);
      expect(first.pros, contains('清晰分层'));
      expect(first.cons, contains('需要设计同步层'));
      // Second option: explicit id kept, recommended defaults false.
      expect(req.options[1].recommended, isFalse);
      expect(req.options[1].id, 'bloc');
    });

    test('rejects wrong type / missing fields / single option', () {
      expect(DecisionRequest.tryParse(null), isNull);
      expect(DecisionRequest.tryParse('nope'), isNull);
      expect(
        DecisionRequest.tryParse(<String, Object?>{
          'type': 'something_else',
          'title': 't',
          'options': [
            {'label': 'a'},
            {'label': 'b'},
          ],
        }),
        isNull,
      );
      expect(
        DecisionRequest.tryParse(<String, Object?>{
          'type': 'decision_request',
          'title': '',
          'options': [
            {'label': 'a'},
            {'label': 'b'},
          ],
        }),
        isNull,
      );
      // Only one valid option → not a decision.
      expect(
        DecisionRequest.tryParse(<String, Object?>{
          'type': 'decision_request',
          'title': 't',
          'options': [
            {'label': 'only'},
            {'no_label': true},
          ],
        }),
        isNull,
      );
    });

    test('allow_custom defaults to false when absent', () {
      final req = DecisionRequest.tryParse(<String, Object?>{
        'type': 'decision_request',
        'title': 't',
        'options': [
          {'label': 'a'},
          {'label': 'b'},
        ],
      });
      expect(req!.allowCustom, isFalse);
    });
  });
}
