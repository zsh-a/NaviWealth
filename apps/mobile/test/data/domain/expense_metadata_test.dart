import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/expense_metadata.dart';

void main() {
  group('ExpenseMetadata', () {
    test('round-trips through encode/decode', () {
      const original = ExpenseMetadata(
        tags: ['lunch', 'team'],
      );

      final decoded = ExpenseMetadata.decode(original.encode());

      expect(decoded, equals(original));
    });

    test('omits empty tags list from JSON to keep diffs small', () {
      const meta = ExpenseMetadata();
      expect(meta.encode(), equals('{}'));
    });

    test('decode returns null for missing / structurally invalid input',
        () {
      expect(ExpenseMetadata.decode(null), isNull);
      expect(ExpenseMetadata.decode(''), isNull);
      expect(ExpenseMetadata.decode('"just a string"'), isNull);
    });

    test('decode throws on invalid JSON — corruption is loud, not silent',
        () {
      expect(() => ExpenseMetadata.decode('not json'), throwsFormatException);
    });

    test('decode tolerates non-string entries in tags', () {
      final m = ExpenseMetadata.decode(
        '{"tags":["ok",42,null,"also-ok"]}',
      );
      expect(m, isNotNull);
      expect(m!.tags, equals(['ok', 'also-ok']));
    });

    test('copyWith preserves untouched fields', () {
      const meta = ExpenseMetadata(tags: ['t1']);
      final copy = meta.copyWith(tags: ['t2']);
      expect(copy.tags, ['t2']);
    });
  });
}
