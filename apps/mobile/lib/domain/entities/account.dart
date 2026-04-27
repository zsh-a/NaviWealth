enum AccountKind { cash, bank, broker, wallet, credit, loan, other }

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.currency,
    required this.openingBalance,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.notes,
    this.archived = false,
    this.deletedAt,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final String currency;
  final double openingBalance;
  final String? institution;
  final String? notes;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Account copyWith({
    String? name,
    AccountKind? kind,
    String? currency,
    double? openingBalance,
    String? institution,
    String? notes,
    bool? archived,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      currency: currency ?? this.currency,
      openingBalance: openingBalance ?? this.openingBalance,
      institution: institution ?? this.institution,
      notes: notes ?? this.notes,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
