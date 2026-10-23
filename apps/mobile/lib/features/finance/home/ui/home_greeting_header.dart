import 'package:flutter/widgets.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Task heading and actions for the domain home.
class HomeGreetingHeader extends StatelessWidget {
  const HomeGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ShellPageHeading(title: l10n.financeOverviewTitle);
  }
}
