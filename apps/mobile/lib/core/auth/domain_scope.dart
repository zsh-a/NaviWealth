/// LifeOS per-user domain opt-in (`docs/lifeos-shell.md` §5, D-1.5).
///
/// FinanceOS is the seed domain — always on. Future domains
/// (HealthOS in D-2, then TimeOS / KnowledgeOS / LivingOS once their
/// triggers fire) ship behind an explicit per-user opt-in so the
/// product can introduce a new domain without breaking single-user
/// installs that don't want it.
///
/// The toggle is a *client* preference today (Phase D-1.5) and a
/// *JWT claim* on the next-issued token: backend sync routes use the
/// claim to filter row-family pulls per domain (see `apps/backend/
/// src/sync/store.rs` and the row-family prefix from D-1.4).
library;

/// Active LifeOS domains. New domains are added here only after their
/// trigger conditions fire (`docs/lifeos-architecture-northstar.md` §4).
/// Until then the enum stays small on purpose — phantom values would
/// invite premature UI / sync wiring.
enum DomainScope {
  finance,
  health;

  /// Wire / storage form. Matches the JWT `domains` claim value and
  /// the row-family prefix `<scope>:`.
  String get wire => switch (this) {
    DomainScope.finance => 'finance',
    DomainScope.health => 'health',
  };

  static DomainScope? tryParse(String value) => switch (value) {
    'finance' => DomainScope.finance,
    'health' => DomainScope.health,
    _ => null,
  };
}

/// The set of domains a user has opted into. FinanceOS is included on
/// every device — it's the seed domain. Other domains default to OFF.
class DomainOptIns {
  DomainOptIns(Set<DomainScope> active)
    : _active = Set<DomainScope>.unmodifiable(<DomainScope>{
        DomainScope.finance,
        ...active,
      });

  /// The shape D-1.5 ships with: every install starts FinanceOS-only.
  static final DomainOptIns financeOnly = DomainOptIns(
    const <DomainScope>{DomainScope.finance},
  );

  factory DomainOptIns.fromWire(Iterable<String> wireValues) {
    final set = <DomainScope>{DomainScope.finance};
    for (final v in wireValues) {
      final parsed = DomainScope.tryParse(v);
      if (parsed != null) set.add(parsed);
    }
    return DomainOptIns(set);
  }

  final Set<DomainScope> _active;

  bool contains(DomainScope scope) => _active.contains(scope);

  /// Unmodifiable view used by callers / serializers.
  Set<DomainScope> get active => _active;

  /// Wire / JWT claim form (sorted for determinism).
  List<String> toWire() {
    final wire = _active.map((s) => s.wire).toList()..sort();
    return wire;
  }

  DomainOptIns withScope(DomainScope scope, {required bool enabled}) {
    final next = <DomainScope>{..._active};
    if (enabled) {
      next.add(scope);
    } else if (scope != DomainScope.finance) {
      // Finance can never be opted out — it's the seed domain.
      next.remove(scope);
    }
    return DomainOptIns(next);
  }

  @override
  bool operator ==(Object other) =>
      other is DomainOptIns &&
      other._active.length == _active.length &&
      other._active.containsAll(_active);

  @override
  int get hashCode => Object.hashAllUnordered(_active);

  @override
  String toString() => 'DomainOptIns(${toWire().join(', ')})';
}
