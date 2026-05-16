import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/intent/ai_context_chip_scope.dart';

class _Probe extends StatelessWidget {
  const _Probe({required this.onChips});
  final void Function(List<AiContextChip> chips, Map<String, Object?> map)
  onChips;

  @override
  Widget build(BuildContext context) {
    final chips = AiContextChipScope.chipsOf(context);
    final map = AiContextChipScope.contextMapOf(context);
    onChips(chips, map);
    return const SizedBox.shrink();
  }
}

void main() {
  group('AiContextChipScope', () {
    testWidgets('returns empty when no scope is mounted', (tester) async {
      late List<AiContextChip> seen;
      late Map<String, Object?> seenMap;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _Probe(
            onChips: (c, m) {
              seen = c;
              seenMap = m;
            },
          ),
        ),
      );
      expect(seen, isEmpty);
      expect(seenMap, isEmpty);
    });

    testWidgets('exposes a single scope\'s chips in declaration order', (
      tester,
    ) async {
      late List<AiContextChip> seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AiContextChipScope(
            chips: const [
              AiContextChip(key: 'route', label: '/home', value: '/home'),
              AiContextChip(key: 'currency', label: 'CNY', value: 'CNY'),
            ],
            child: _Probe(onChips: (c, _) => seen = c),
          ),
        ),
      );
      expect(seen.map((c) => c.key).toList(), <String>['route', 'currency']);
    });

    testWidgets('inner scope overrides outer scope on duplicate key', (
      tester,
    ) async {
      late List<AiContextChip> seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AiContextChipScope(
            chips: const [
              AiContextChip(key: 'route', label: 'outer', value: 'outer'),
              AiContextChip(key: 'currency', label: 'CNY', value: 'CNY'),
            ],
            child: AiContextChipScope(
              chips: const [
                AiContextChip(key: 'route', label: 'inner', value: 'inner'),
                AiContextChip(
                  key: 'timeframe',
                  label: 'last 30d',
                  value: 'last_30d',
                ),
              ],
              child: _Probe(onChips: (c, _) => seen = c),
            ),
          ),
        ),
      );
      // Outer first, inner overrides 'route', and adds 'timeframe' last.
      expect(
        seen.map((c) => '${c.key}=${c.value}').toList(),
        <String>['route=inner', 'currency=CNY', 'timeframe=last_30d'],
      );
    });

    testWidgets('contextMapOf flattens chips to a map', (tester) async {
      late Map<String, Object?> seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AiContextChipScope(
            chips: const [
              AiContextChip(key: 'route', label: '/x', value: '/x'),
              AiContextChip(
                key: 'selection',
                label: '3 rows',
                value: <String>['a', 'b', 'c'],
              ),
            ],
            child: _Probe(onChips: (_, m) => seen = m),
          ),
        ),
      );
      expect(seen['route'], '/x');
      expect(seen['selection'], <String>['a', 'b', 'c']);
    });
  });
}
