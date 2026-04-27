import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';

void main() {
  testWidgets('NaviWealthApp boots into the home shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NaviWealthApp()));
    await tester.pumpAndSettle();

    expect(find.text('总览'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
