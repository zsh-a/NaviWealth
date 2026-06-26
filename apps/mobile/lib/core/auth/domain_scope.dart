/// LifeOS per-user domain opt-in (`docs/lifeos-shell.md` §5).
///
/// FinanceOS is the seed domain and always on. Additional domains ship
/// behind an explicit per-user opt-in so a user can enable LifeOS areas
/// incrementally without changing the Finance-only default.
///
/// The toggle is stored as a client preference and mirrored into the
/// next-issued JWT `domains` claim. Backend sync routes use that claim
/// to filter row-family pulls per domain (see `apps/backend/src/sync/
/// store.rs` and the row-family prefix contract).
library;

/// Active LifeOS domains. New domains are added here only after their
/// trigger conditions fire (`docs/lifeos-architecture-northstar.md` §4).
/// Until then the enum stays small on purpose — phantom values would
/// invite premature UI / sync wiring.
enum DomainScope {
  finance,
  health,
  knowledge,
  execution;

  /// Wire / storage form. Matches the JWT `domains` claim value and
  /// the row-family prefix `<scope>:`.
  String get wire => switch (this) {
    DomainScope.finance => 'finance',
    DomainScope.health => 'health',
    DomainScope.knowledge => 'knowledge',
    DomainScope.execution => 'execution',
  };

  static DomainScope? tryParse(String value) => switch (value) {
    'finance' => DomainScope.finance,
    'health' => DomainScope.health,
    'knowledge' => DomainScope.knowledge,
    'execution' => DomainScope.execution,
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

  /// Every install starts FinanceOS-only.
  static final DomainOptIns financeOnly = DomainOptIns(const <DomainScope>{
    DomainScope.finance,
  });

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
