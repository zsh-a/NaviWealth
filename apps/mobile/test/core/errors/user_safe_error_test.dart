import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/errors/user_safe_error.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _FriendlyError implements UserFacingError {
  const _FriendlyError(this.userMessage);

  @override
  final String userMessage;
}

void main() {
  testWidgets('technical errors are replaced by localized safe copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Text(
            userSafeErrorMessage(
              context,
              Exception('MutationStamper requires an authenticated session'),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text("We couldn't complete that. Please try again."),
      findsOneWidget,
    );
    expect(find.textContaining('MutationStamper'), findsNothing);
  });

  testWidgets('explicit user-facing errors preserve their message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(
            userSafeErrorMessage(
              context,
              const _FriendlyError('Choose a valid date.'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Choose a valid date.'), findsOneWidget);
  });
}
