import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'formatters.dart';

/// Builds an [AppFormatters] for the active locale. Read with
/// `ref.watch(appFormattersProvider(Localizations.localeOf(context)))` or use
/// [AppFormattersScope] inside a widget tree.
final appFormattersProvider = Provider.family<AppFormatters, Locale>((
  ref,
  locale,
) {
  return AppFormatters(locale: locale);
});

/// Convenience accessor that resolves the active locale from the widget tree.
extension AppFormattersContext on BuildContext {
  AppFormatters formatters(WidgetRef ref) {
    return ref.read(appFormattersProvider(Localizations.localeOf(this)));
  }
}
