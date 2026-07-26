import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/health/composition/health_domain_shell.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  // `lookupAppLocalizations` works for any const-supported locale —
  // bootstrap uses 'en' so we mirror that here. The shell spec doesn't
  // read l10n today (D-2.3 keeps strings as literals); the param is
  // accepted for parity with `financeDomainShell(l10n)`.
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('healthDomainShell(l10n)', () {
    test('scope and label identify HealthOS', () {
      final spec = healthDomainShell(l10n);
      expect(spec.scope, DomainScope.health);
      expect(spec.label, 'HealthOS');
    });

    test('exposes Today / Trends tabs in IA order', () {
      final spec = healthDomainShell(l10n);
      expect(spec.tabs.map((t) => t.label).toList(), ['Today', 'Trends']);
      expect(spec.tabs.map((t) => t.routePath).toList(), [
        AppRoutes.healthToday,
        AppRoutes.healthTrend,
      ]);
    });

    test('every tab carries both default + selected icons', () {
      final spec = healthDomainShell(l10n);
      for (final tab in spec.tabs) {
        // Both icon and selectedIcon must be non-null. Lucide icons are
        // outline-style by design; the active-tab cue comes from color,
        // not a filled variant.
        expect(tab.icon, isNotNull, reason: 'tab ${tab.label} icon');
        expect(
          tab.selectedIcon,
          isNotNull,
          reason: 'tab ${tab.label} selectedIcon',
        );
      }
    });
  });
}
