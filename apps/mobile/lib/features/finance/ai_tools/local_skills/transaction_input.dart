/// Neutral input shape consumed by every rules skill in
/// `features/finance/ai_tools/local_skills/`.
///
/// Skills do not read from Drift or Riverpod directly. Feature code
/// (typically a thin adapter living next to the relevant repository)
/// converts domain types like `Expense` / `JournalEntry` into
/// [TransactionInput] before invoking a skill, then maps any
/// [Classification] / [RecurringPattern] / [TransferMatch] /
/// [RefundMatch] result back to its domain category id, recurring
/// pattern id, etc.
library;

class TransactionInput {
  const TransactionInput({
    required this.id,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    this.accountId,
    this.categoryId,
  });

  /// Stable id (Drift row id, journal entry id, etc.). Skills use it
  /// to refer back to the original record when emitting matches.
  final String id;

  /// Raw description string the skill matches against (rules /
  /// merchant key extraction). Never logged outside the device.
  final String description;

  /// Signed integer minor units. Negative = outflow (expense / debit),
  /// positive = inflow. String for cross-language safety; skills
  /// parse internally via `int.tryParse`.
  final String amountMinor;

  /// ISO 4217 currency code. Skills only compare entries with the
  /// same currency unless explicitly designed otherwise.
  final String currency;

  /// UTC instant the transaction occurred. Skills compare dates in
  /// the wallclock UTC sense — daylight savings is the caller's
  /// problem.
  final DateTime occurredAt;

  /// Optional account id. Required by [transferMatcher] (it filters
  /// out same-account pairs); other skills ignore it.
  final String? accountId;

  /// Optional pre-existing category. [txnClassifier] returns `null`
  /// when this is non-null and the user is happy with it — skills
  /// never overwrite a hand-set category.
  final String? categoryId;
}

/// Parsed signed integer view of [TransactionInput.amountMinor].
/// Lenient: returns `0` if the string can't be parsed (the input came
/// from a foreign system that uses a different format).
int parseAmountMinor(String s) => int.tryParse(s) ?? 0;
