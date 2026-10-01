import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '../support/test_app_theme.dart';

void main() {
  testWidgets(
    'refresh keeps resolved content and initial loading uses a skeleton',
    (tester) async {
      var pending = Completer<String>();
      final contentProvider = FutureProvider<String>((_) => pending.future);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: buildTestAppTheme,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ref
                      .watch(contentProvider)
                      .whenOrLoading(context: context, data: Text.new);
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SkeletonBox), findsWidgets);
      pending.complete('Known content');
      await tester.pump();
      await tester.pump();
      expect(find.text('Known content'), findsOneWidget);
      pending = Completer<String>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Consumer)),
      );
      container.invalidate(contentProvider);
      await tester.pump();
      expect(find.text('Known content'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);
      pending.complete('Fresh content');
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh content'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
