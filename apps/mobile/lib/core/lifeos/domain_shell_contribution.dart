part of 'domain_pack.dart';

/// Shell contributions owned by one domain.
final class DomainShellContribution {
  const DomainShellContribution({
    this.navigation,
    this.accent,
    this.commandPaletteEntriesBuilder,
    this.settingsSpec,
    this.settingsRoutesBuilder,
    this.notificationSettingsBuilder,
  });

  /// A navigable domain supplies its routes, shell spec and tab roots together.
  final DomainNavigation? navigation;

  /// Optional chrome identity hue (switcher chip, switcher sheet rows, dock
  /// tab tint). Null falls back to the global primary — zero behavior change
  /// for packs that do not opt in. Status and market colors stay semantic;
  /// see `design_system/theme/domain_accent.dart`.
  final DomainAccent? accent;

  /// Cmd-K command palette contributions. Null when the domain has no
  /// palette entries yet. Non-null builders are invoked with the active
  /// locale's [AppLocalizations] and their entries are concatenated into
  /// the shell palette in domain order.
  final DomainCommandPaletteBuilder? commandPaletteEntriesBuilder;

  /// Settings → Domains toggle metadata and optional domain detail route.
  /// Null when the domain has no settings surface yet.
  final DomainSettingsSpec? settingsSpec;

  /// Top-level Settings routes contributed by this domain.
  final DomainSettingsRoutesBuilder? settingsRoutesBuilder;

  /// Rows contributed to Settings → Notifications when this domain is active.
  /// Global notification permission and master enablement stay in Settings;
  /// domain-specific notification toggles remain with the owning domain.
  final DomainNotificationSettingsBuilder? notificationSettingsBuilder;
}

/// Navigation contributions owned by one domain.
final class DomainNavigation {
  const DomainNavigation({
    required this.shellSpecBuilder,
    required this.shellRouteBuilder,
    required this.tabPaths,
    this.additionalPathPrefixes = const <String>[],
    this.reviewRoutePath,
    this.deferredPreloader,
  });

  /// Localised shell spec (4-tab IA, color, dock placement), declared
  /// together with routes and tab roots.
  final DomainShellSpecBuilder shellSpecBuilder;

  /// Constructs the domain's `StatefulShellRoute` (mounted under the
  /// outer `AppDockShell` in `router_builder.dart`).
  final DomainShellRouteBuilder shellRouteBuilder;

  /// Top-level tab paths the domain claims. Used by
  /// `domainForRoute` to map an active path back to its domain and
  /// by `primaryTabPathsProvider` to drive the system back handler
  /// + Cmd-1..4 tab switcher. The l10n-bound [shellSpecBuilder] still
  /// owns labels + icons.
  final List<String> tabPaths;

  /// Extra route prefixes the domain owns that are **not** top-level
  /// tabs (and therefore don't belong in [tabPaths]). Used only by
  /// `domainForRoute` for owner lookup; the system back handler does
  /// not treat these as primary roots. FinanceOS uses this for
  /// `/cashflow*` which lives under the Finance shell but isn't a
  /// 4-tab destination.
  final List<String> additionalPathPrefixes;

  /// Optional contextual review destination surfaced by the Life hub.
  /// Review pages stay domain-owned and do not consume a permanent shell tab.
  final String? reviewRoutePath;

  /// Test-only preloader for every `deferred as` library this domain's
  /// routes can reach. Null when the domain ships no deferred libs.
  final DomainDeferredPreloader? deferredPreloader;
}
