/// Narration strings for ledger entries mirrored from the options journal.
///
/// Narrations are persisted on the journal entry, so they are generated in
/// the user's active locale at write time (same policy as the cached
/// opportunity explanations).
library;

abstract interface class OptionsLedgerNarrations {
  String premium(String optionSymbol);
  String closeDebit(String optionSymbol);
  String putAssigned(String symbol);
  String callAssigned(String symbol);
  String leapsOpen(String optionSymbol);
  String leapsClose(String optionSymbol);
  String leapsExercise(String optionSymbol);
  String leapsExpired(String optionSymbol);
}

/// English fallback used by tests and as the default wiring.
class DefaultOptionsLedgerNarrations implements OptionsLedgerNarrations {
  const DefaultOptionsLedgerNarrations();

  @override
  String premium(String optionSymbol) => 'Options premium $optionSymbol';

  @override
  String closeDebit(String optionSymbol) => 'Options close debit $optionSymbol';

  @override
  String putAssigned(String symbol) => 'Put assigned $symbol';

  @override
  String callAssigned(String symbol) => 'Covered call assigned $symbol';

  @override
  String leapsOpen(String optionSymbol) => 'LEAPS open $optionSymbol';

  @override
  String leapsClose(String optionSymbol) => 'LEAPS close $optionSymbol';

  @override
  String leapsExercise(String optionSymbol) => 'LEAPS exercise $optionSymbol';

  @override
  String leapsExpired(String optionSymbol) => 'LEAPS expired $optionSymbol';
}
