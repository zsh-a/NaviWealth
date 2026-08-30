/// Cross-domain seam for the AI chat header summary chip + the
/// empty-state suggestion tiles (`docs/architecture/lifeos-shell.md` §4, D-1.6b).
///
/// The chip renders a rolling pulse of facts about whatever life
/// signals the active domain considers worth surfacing. Finance currently
/// contributes net-worth direction, expense anomalies, and deposit
/// maturities; other domains can contribute analogous facts through the
/// app composition root. Each fact carries its own localised one-liner so
/// the renderer is fully domain-neutral.
///
/// **Why a builder closure rather than a typed payload Provider**:
/// fact text is `AppLocalizations`-formatted (e.g. "Net worth +2.3%
/// this month"), but Riverpod providers cannot depend on
/// `BuildContext`. The domain provider therefore returns a
/// `Function(AppLocalizations) → AiContextSummary` that captures
/// the raw data and formats lazily at render time.
///
/// **Relationship to memory layer**: this is intentionally a
/// display-only summary (no AI context input). The ContextPack
/// pipeline used for chat turns is `chat_trace_prep.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';

@immutable
class AiContextSummary {
  const AiContextSummary({this.facts = const <AiContextFact>[]});

  static const AiContextSummary empty = AiContextSummary();

  /// In render order. The header chip shows every fact; the chat
  /// empty-state shows up to three of those that carry a non-null
  /// [AiContextFact.suggestion] (see `ai_chat_page.dart`).
  final List<AiContextFact> facts;

  bool get isEmpty => facts.isEmpty;
}

/// A single observation worth surfacing on the AI page. Each fact is
/// localised + formatted by the producing domain — the shell renderer
/// only knows how to draw it (icon + text + tone color).
@immutable
class AiContextFact {
  const AiContextFact({
    required this.id,
    required this.icon,
    required this.tone,
    required this.text,
    this.suggestion,
  });

  /// Stable identifier, e.g. `fin:networth_pct`. Domain prefix is
  /// encouraged so a Health fact never clashes with a Finance fact.
  final String id;
  final IconData icon;
  final AiContextTone tone;

  /// Localised one-line summary, e.g. "Net worth +2.3% this month".
  final String text;

  /// Optional localised tile prompt used by the chat empty-state.
  /// When present and tapped, the tile sends [suggestion] as the next
  /// user turn. Facts without a suggestion still render in the header
  /// chip but never appear as a tile.
  final String? suggestion;
}

/// Semantic colour bucket the renderer maps to a theme token.
/// Kept small on purpose — shell shouldn't pick HEX values.
enum AiContextTone { positive, neutral, attention }

/// Builds the summary at render time so domain producers can capture
/// raw upstream data without committing to a locale.
typedef AiContextSummaryBuilder = AiContextSummary Function(
  AppLocalizations l10n,
);

/// Active builder for the current build. Default returns
/// [AiContextSummary.empty] for every locale, so a domain-less build
/// renders nothing (the header chip and empty-state tiles collapse).
/// Bootstrap overrides this with the active domain's composer.
final aiContextSummaryProvider = Provider<AiContextSummaryBuilder>(
  (ref) =>
      (_) => AiContextSummary.empty,
);
