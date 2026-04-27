import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';

void main() {
  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NaviWealthApp()));
    await tester.pumpAndSettle();

    // Home page localized title — "Overview" in en-US, "总览" in zh-CN.
    // Test environment falls back to the first supported locale (en).
    expect(find.text('Overview'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
