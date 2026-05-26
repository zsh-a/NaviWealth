import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import 'chat_rail_content.dart';

/// Localised selector: given the active [AppLocalizations], returns the
/// rail content the AI chat surface should render.
///
/// Pulling `AppLocalizations` through as a parameter (rather than
/// reading it inside the provider) keeps the provider free of
/// `BuildContext` while still letting domain implementations format
/// numbers / dates with the user's locale.
typedef ChatRailContentSelector = List<ChatRailContent> Function(
  AppLocalizations l10n,
);

/// Cross-domain rail content the AI chat surface renders
/// (`docs/lifeos-shell.md` §4, D-1.6).
///
/// Default: a selector that always returns an empty list — the shell-
/// only build (no domain registered) renders an empty rail rather than
/// crashing.
///
/// Each domain (Finance today, HealthOS once D-2 lands) overrides this
/// provider in `bootstrap.dart` with its own selector. Multi-domain
/// builds will combine selectors by concatenation.
final chatRailContentSelectorProvider = Provider<ChatRailContentSelector>(
  (ref) => (_) => const <ChatRailContent>[],
);
