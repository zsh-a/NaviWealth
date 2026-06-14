import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/features/knowledge/ui/_widgets.dart';

Future<T> _withLocale<T>(
  WidgetTester tester,
  Locale locale,
  T Function(BuildContext context) read,
) async {
  late T result;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          result = read(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  testWidgets('knowledgeMonthDayFromIso formats month/day by locale', (
    tester,
  ) async {
    final zh = await _withLocale(
      tester,
      const Locale('zh'),
      (context) => knowledgeMonthDayFromIso(context, '2026-06-07T09:30:00Z'),
    );
    expect(zh, '6月7日');

    final en = await _withLocale(
      tester,
      const Locale('en'),
      (context) => knowledgeMonthDayFromIso(context, '2026-06-07T09:30:00Z'),
    );
    expect(en, 'Jun 7');
  });

  testWidgets(
    'knowledgeDateFromIso fallback does not truncate arbitrary text',
    (tester) async {
      final prefixed = await _withLocale(
        tester,
        const Locale('en'),
        (context) => knowledgeDateFromIso(context, '2026-06-07 invalid tail'),
      );
      expect(prefixed, '2026-06-07');

      final arbitrary = await _withLocale(
        tester,
        const Locale('en'),
        (context) => knowledgeDateFromIso(context, 'not-a-date-but-long'),
      );
      expect(arbitrary, 'not-a-date-but-long');
    },
  );
}
