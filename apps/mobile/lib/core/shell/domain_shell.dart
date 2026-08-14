/// Multi-domain IA shell seam (`docs/architecture/lifeos-shell.md` §3, D-1.8).
///
/// Each active LifeOS domain declares a [DomainShellSpec] (label, icon,
/// root tabs) and the app shell renders them. FinanceOS is always
/// present; HealthOS, KnowledgeOS, and ExecutionOS appear when their
/// domain opt-ins are enabled. The dock/switcher becomes visible once
/// two or more specs are active.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../auth/domain_scope.dart';
import '../auth/providers.dart';

/// A single tab destination inside one domain's shell. Mirrors the
/// pre-D-1.8 `_NavDestination` shape so app_shell can render either
/// the legacy single-domain layout or a multi-domain dock from the
/// same data.
class DomainShellTab {
  const DomainShellTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.routePath,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// `go_router` path the tab maps to (Finance: `/today`, etc.).
  /// Used for deep-link → tab resolution when the domain dock
  /// switches the active domain.
  final String routePath;
}

/// Definition of a single LifeOS domain's shell. Lives at
/// `features/<domain>/composition/<domain>_domain_shell.dart` and
/// is registered into [activeDomainShellsProvider] by `bootstrap.dart`.
class DomainShellSpec {
  const DomainShellSpec({
    required this.scope,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.tabs,
    this.hiddenTabs = const <DomainShellTab>[],
  });

  /// Domain identity. Multi-domain dispatch (sync prefix, JWT claim,
  /// AI tool registry) all key off this enum.
  final DomainScope scope;

  /// Display name in the dock / switcher ("FinanceOS", "HealthOS",
  /// "KnowledgeOS", "ExecutionOS").
  final String label;

  /// Icon shown in the dock / switcher.
  final IconData icon;

  /// Active-state variant of [icon].
  final IconData selectedIcon;

  /// Domain-local tab list rendered by the nav chrome (dock / rail /
  /// sidebar / switcher). Order matches the in-domain nav order
  /// (Finance: Today / Activity / Wealth / Plan).
  final List<DomainShellTab> tabs;

  /// Routable shell branches that are intentionally absent from the nav
  /// chrome — reachable via header actions, the command palette, or
  /// contextual signals instead of a permanent tab (Knowledge/Execution
  /// Review). They still count as branches of the domain's
  /// `StatefulShellRoute` (declared after the visible branches) and still
  /// resolve through [specOwnsPath] / [activeSpecForPath].
  final List<DomainShellTab> hiddenTabs;
}

/// Active LifeOS domain shells, in render order.
///
/// Default: empty — a build with no domain registered renders without
/// the dock chrome (see `app_dock_shell.dart`). `bootstrap.dart`
/// overrides this with the union of every domain the user has opted
/// into via [domainOptInsProvider].
///
/// FinanceOS is always registered. Optional domain specs are included
/// when their opt-ins are active.
final activeDomainShellsProvider = Provider<List<DomainShellSpec>>(
  (ref) => const <DomainShellSpec>[],
);

/// True when the user has at least two domains active. Drives the
/// dock visibility. Single-domain builds hide the dock chrome.
final domainDockVisibleProvider = Provider<bool>(
  (ref) => ref.watch(activeDomainShellsProvider).length > 1,
);

/// Helper that gates a domain spec on its opt-in. Use from
/// `bootstrap.dart` to compose the active set:
///
/// ```dart
/// activeDomainShellsProvider.overrideWith((ref) {
///   final opts = ref.watch(domainOptInsProvider).valueOrNull
///       ?? DomainOptIns.financeOnly;
///   final l10n = ...; // resolved at render time
///   return [
///     financeDomainShell(l10n),
///     if (opts.contains(DomainScope.health)) healthDomainShell(l10n),
///     if (opts.contains(DomainScope.knowledge)) knowledgeDomainShell(l10n),
///     if (opts.contains(DomainScope.execution)) executionDomainShell(l10n),
///   ];
/// });
/// ```
DomainOptIns currentOptIns(Ref ref) =>
    ref.watch(domainOptInsProvider).value ?? DomainOptIns.financeOnly;

/// Localised builder hook — domains expose a function that takes
/// [AppLocalizations] so labels stay i18n-clean.
typedef DomainShellSpecBuilder =
    DomainShellSpec Function(AppLocalizations l10n);

// ─── Path → domain spec helpers ───
//
// Used by both the desktop dock (active highlight) and the long-press
// switcher sheet (current selection). Keeping the predicate in one
// place stops the two call sites from drifting on what "this domain
// owns the active route" means.

/// True when [path] equals one of [spec]'s tab routes (visible or hidden)
/// or sits below it.
bool specOwnsPath(DomainShellSpec spec, String path) {
  for (final t in spec.tabs) {
    if (path == t.routePath || path.startsWith('${t.routePath}/')) {
      return true;
    }
  }
  for (final t in spec.hiddenTabs) {
    if (path == t.routePath || path.startsWith('${t.routePath}/')) {
      return true;
    }
  }
  return false;
}

/// First spec in [specs] that owns [activePath]; falls back to the
/// first registered spec when nothing matches (e.g. cross-domain root
/// route like `/today`).
DomainShellSpec activeSpecForPath(
  List<DomainShellSpec> specs,
  String activePath,
) {
  for (final s in specs) {
    if (specOwnsPath(s, activePath)) return s;
  }
  return specs.first;
}
