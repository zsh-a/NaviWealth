import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/ai_pill.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpPill(
  WidgetTester tester, {
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, appChild) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: textScaler),
          child: appChild!,
        );
      },
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('bounded long label truncates safely at 2x text scale', (
    tester,
  ) async {
    const label =
        'Review every imported transaction before adding it to the ledger';
    final semantics = tester.ensureSemantics();

    await _pumpPill(
      tester,
      textScaler: const TextScaler.linear(2),
      child: const Center(
        child: SizedBox(
          width: 180,
          child: AiPill(label: label, leading: SizedBox(width: 12, height: 12)),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(label));
    final richText = find.descendant(
      of: find.text(label),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(richText);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AiPill)).width, 180);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(tester.getSemantics(find.text(label)).label, label);
    semantics.dispose();
  });

  testWidgets('unbounded short pill stays compact and fully interactive', (
    tester,
  ) async {
    const label = 'Review';
    const pillKey = ValueKey('pill');
    const leadingKey = ValueKey('leading');
    var taps = 0;

    await _pumpPill(
      tester,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AiPill(
          key: pillKey,
          label: label,
          leading: const SizedBox(key: leadingKey, width: 12, height: 12),
          onTap: () => taps += 1,
        ),
      ),
    );

    final pillRect = tester.getRect(find.byKey(pillKey));
    final leadingRect = tester.getRect(find.byKey(leadingKey));
    final labelRect = tester.getRect(find.text(label));

    expect(tester.takeException(), isNull);
    expect(pillRect.width, lessThan(160));
    expect(labelRect.left - leadingRect.right, AppSpacing.s6);

    await tester.tapAt(Offset(pillRect.left + 2, pillRect.center.dy));
    await tester.pump();
    expect(taps, 1);
  });
}
