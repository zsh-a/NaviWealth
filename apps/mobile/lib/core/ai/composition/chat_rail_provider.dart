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
/// (`docs/architecture/lifeos-shell.md` §4).
///
/// Default: a selector that always returns an empty list — the shell-
/// only build (no domain registered) renders an empty rail rather than
/// crashing.
///
/// Domain composition overrides this provider with the active selector.
/// Multi-domain builds can combine selectors by concatenation without
/// the chat surface importing any domain implementation.
final chatRailContentSelectorProvider = Provider<ChatRailContentSelector>(
  (ref) =>
      (_) => const <ChatRailContent>[],
);
