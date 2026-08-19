import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_inbox_providers.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';
import 'package:naviwealth/features/finance/inbox/ui/financial_inbox_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('loading does not claim the inbox is empty', (tester) async {
    final pending = Completer<List<FinancialInboxItem>>();
    await tester.pumpWidget(
      _wrap(financialInboxProvider.overrideWith((_) => pending.future)),
    );
    await tester.pump();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      find.byKey(const ValueKey<String>('financial-inbox.loading')),
      findsOneWidget,
    );
    expect(find.text(l10n.financialInboxEmptyTitle), findsNothing);
  });

  testWidgets('empty data and load errors remain distinct', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      _wrap(financialInboxProvider.overrideWith((_) async => const [])),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.financialInboxEmptyTitle), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        financialInboxProvider.overrideWith(
          (_) async => throw StateError('unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.commonLoadFailed), findsOneWidget);
    expect(find.text(l10n.financialInboxEmptyTitle), findsNothing);
  });
}

Widget _wrap(Override override) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [override],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: const Scaffold(body: FinancialInboxCard()),
      ),
    ),
  );
}
