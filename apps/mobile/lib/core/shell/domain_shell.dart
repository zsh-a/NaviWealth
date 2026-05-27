/// Multi-domain IA shell seam (`docs/lifeos-shell.md` §3, D-1.8).
///
/// Phase D-1.8 ships the *abstraction*: each active LifeOS domain
/// declares a [DomainShellSpec] (label, icon, root tabs) and the
/// app shell renders them. Today only FinanceOS is active, so the
/// shell looks identical to the pre-D-1.8 UI. Phase D-2 lands a
/// HealthOS shell spec alongside, and the left domain dock (shell
/// §3 Option B) becomes visible once two specs are registered.
///
/// **Decision gate (shell §3 复述)**: dogfood 2 weeks after D-2 to
/// confirm Option B (left dock) over Option A (top switcher). The
/// abstraction below is shape-compatible with either presentation.
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
  });

  /// Domain identity. Multi-domain dispatch (sync prefix, JWT claim,
  /// AI tool registry) all key off this enum.
  final DomainScope scope;

  /// Display name in the dock / switcher ("FinanceOS", "HealthOS").
  /// Phase D-1.8 leaves it as a literal — l10n can be added when
  /// HealthOS ships and the dock becomes visible.
  final String label;

  /// Icon shown in the dock / switcher.
  final IconData icon;

  /// Active-state variant of [icon].
  final IconData selectedIcon;

  /// Domain-local tab list. Order matches the in-domain nav order
  /// (Finance: Today / Activity / Wealth / Plan).
  final List<DomainShellTab> tabs;
}

/// Active LifeOS domain shells, in render order.
///
/// Default: empty — a build with no domain registered renders without
/// the dock chrome (see `app_dock_shell.dart`). `bootstrap.dart`
/// overrides this with the union of every domain the user has opted
/// into via [domainOptInsProvider].
///
/// Phase D-1.8: only FinanceOS is ever registered, so the dock is
/// always 1-entry and stays hidden. Phase D-2 will append a HealthOS
/// spec when the user enables the Health opt-in.
final activeDomainShellsProvider = Provider<List<DomainShellSpec>>(
  (ref) => const <DomainShellSpec>[],
);

/// True when the user has at least two domains active. Drives the
/// dock visibility — single-domain builds look identical to the
/// pre-D-1.8 single-shell layout.
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
///     if (opts.contains(DomainScope.health)) healthDomainShellPlaceholder,
///   ];
/// });
/// ```
DomainOptIns currentOptIns(Ref ref) =>
    ref.watch(domainOptInsProvider).value ?? DomainOptIns.financeOnly;

/// Localised builder hook — domains expose a function that takes
/// [AppLocalizations] so labels stay i18n-clean. Phase D-2 will use
/// this for the Health domain. Provided here as a reference type
/// rather than enforced because Finance currently builds its spec
/// inline in `bootstrap.dart`.
typedef DomainShellSpecBuilder = DomainShellSpec Function(AppLocalizations l10n);
