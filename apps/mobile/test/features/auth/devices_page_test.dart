import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_api_client.dart';
import 'package:naviwealth/core/auth/auth_errors.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/auth/ui/devices_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../support/test_app_theme.dart';

class _FailingDevicesNotifier extends DevicesNotifier {
  @override
  Future<DevicesResponse> build() async {
    throw AuthException(
      AuthErrorKind.unknown,
      message: 'unexpected JSON shape from /auth/devices',
    );
  }
}

void main() {
  testWidgets('does not render raw authentication error details', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [devicesProvider.overrideWith(_FailingDevicesNotifier.new)],
        child: MaterialApp(
          builder: buildTestAppTheme,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const DevicesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load your devices."), findsOneWidget);
    expect(
      find.text("We couldn't complete that. Please try again."),
      findsOneWidget,
    );
    expect(find.textContaining('unexpected JSON shape'), findsNothing);
    expect(find.textContaining('/auth/devices'), findsNothing);
  });
}
