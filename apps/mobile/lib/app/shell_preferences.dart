import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/preferences/theme_preferences.dart';

/// Persisted desktop-shell preferences (FIR-106).
///
/// The two values driven through here both belong to the desktop master-
/// detail experience and are user-tweakable from the UI:
///
///  * `sidebarCollapsed` — `true` if the sidebar is in its 72dp icon-only
///    rail mode, `false` if it's in its 240dp labelled mode. Toggled via
///    `Cmd/Ctrl+B` and the chevron at the bottom of the sidebar.
///  * `masterPaneWidth` — the user's preferred width for the master list
///    pane, in logical pixels. Clamped to `[320, 520]` at read time so a
///    stale preference from a previous build can't render off-screen.
const String _kSidebarCollapsedKey = 'naviwealth.shell.sidebar_collapsed';
const String _kMasterPaneWidthKey = 'naviwealth.shell.master_pane_width';
const String _kPortfolioViewKey = 'naviwealth.shell.portfolio_view';

/// Default width for the master list pane on desktop. 380dp is the value
/// quoted in FIR-106 — wide enough for a primary asset row + delta chip
/// without truncation, narrow enough to leave the detail pane the bulk
/// of a 1240dp window.
const double kMasterPaneDefaultWidth = 380;
const double kMasterPaneMinWidth = 320;
const double kMasterPaneMaxWidth = 520;
const double kSidebarExpandedWidth = 240;
const double kSidebarCollapsedWidth = 72;

/// Maximum content width when the sidebar is collapsed. Keeps text columns
/// from running wider than the eye can comfortably scan on a 27" monitor.
const double kCollapsedContentMaxWidth = 1320;

final sidebarCollapsedProvider =
    StateNotifierProvider<SidebarCollapsedController, bool>((ref) {
      return SidebarCollapsedController(ref.watch(sharedPreferencesProvider));
    });

final masterPaneWidthProvider =
    StateNotifierProvider<MasterPaneWidthController, double>((ref) {
      return MasterPaneWidthController(ref.watch(sharedPreferencesProvider));
    });

final portfolioViewProvider =
    StateNotifierProvider<PortfolioViewController, PortfolioViewMode>((ref) {
      return PortfolioViewController(ref.watch(sharedPreferencesProvider));
    });

enum PortfolioViewMode { assets, account, currency, assetClass }

class SidebarCollapsedController extends StateNotifier<bool> {
  SidebarCollapsedController(this._prefs)
    : super(_prefs.getBool(_kSidebarCollapsedKey) ?? false);

  final SharedPreferences _prefs;

  Future<void> set(bool collapsed) async {
    if (collapsed == state) return;
    state = collapsed;
    await _prefs.setBool(_kSidebarCollapsedKey, collapsed);
  }

  Future<void> toggle() => set(!state);
}

class MasterPaneWidthController extends StateNotifier<double> {
  MasterPaneWidthController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static double _load(SharedPreferences prefs) {
    final raw = prefs.getDouble(_kMasterPaneWidthKey);
    if (raw == null) return kMasterPaneDefaultWidth;
    return raw.clamp(kMasterPaneMinWidth, kMasterPaneMaxWidth);
  }

  Future<void> set(double width) async {
    final clamped = width.clamp(kMasterPaneMinWidth, kMasterPaneMaxWidth);
    if (clamped == state) return;
    state = clamped;
    await _prefs.setDouble(_kMasterPaneWidthKey, clamped);
  }
}

class PortfolioViewController extends StateNotifier<PortfolioViewMode> {
  PortfolioViewController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static PortfolioViewMode _load(SharedPreferences prefs) {
    final raw = prefs.getString(_kPortfolioViewKey);
    return PortfolioViewMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => PortfolioViewMode.assets,
    );
  }

  Future<void> set(PortfolioViewMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_kPortfolioViewKey, mode.name);
  }
}
