/// Window and content breakpoints used across the app.
///
/// Macro layout follows the five Material adaptive width classes. Widgets
/// that sit inside shell chrome still make local decisions from their own
/// constraints using the content breakpoints below.
class Breakpoints {
  const Breakpoints._();

  /// Compact → medium. Phones in portrait are normally below this value.
  static const double mobile = 600;

  /// Medium → expanded. Most tablets in landscape reach this width.
  static const double expanded = 840;

  /// Expanded → large. Large tablets and small desktop windows reach this.
  static const double large = 1200;

  /// Large → extra-large. Wide desktop workspaces may expose a third pane.
  static const double extraLarge = 1600;

  /// Compact → medium height. Important for phones in landscape and short
  /// resizable desktop windows where tall navigation groups must condense.
  static const double mediumHeight = 480;

  /// Medium → expanded height.
  static const double expandedHeight = 900;

  /// Legacy semantic name retained as the large-workspace threshold while
  /// callers migrate to [AppWindowClass].
  static const double desktop = large;

  /// Window width at which the application shell expands its compact rail
  /// into the full desktop sidebar. Shell chrome must use this token against
  /// the total viewport width so nested navigation rails do not shift the
  /// breakpoint.
  ///
  /// Aliases [large]. Shell chrome reads the total window, not the remaining
  /// content width after navigation.
  static const double shellDesktop = desktop;

  /// Width at which a desktop window can afford the labelled 240dp sidebar
  /// without regressing the usable canvas at the 1200dp shell transition.
  /// Below this threshold desktop chrome stays icon-only while preserving the
  /// user's persisted expanded/collapsed preference for wider windows.
  static const double shellExpandedSidebar = 1360;

  /// Threshold for master/detail and supporting-pane compositions. Bento
  /// grids derive their columns from a minimum tile width instead.
  static const double contentTwoColumn = 1024;

  /// Threshold for dense metric grids that can safely introduce a second
  /// compact column. This is not a three-column Bento threshold.
  static const double contentThreeColumn = 720;

  // ── Sub-mobile module thresholds & overlay caps (blueprint §7.1) ────────
  // Collapse of the ad-hoc 320/360/390/420/520/560 literals scattered
  // through feature files: pick from this ladder, never a new number.

  /// Below this a horizontal module row stacks vertically (quick actions,
  /// dense form rows on very narrow phones / split-screen).
  static const double compactModule = 320;

  /// Below this compact cards drop secondary columns / captions.
  static const double compactContent = 360;

  /// Single form column cap, and the threshold under which form layouts
  /// tighten (auth pages, unlock gates, narrow editors).
  static const double formColumn = 420;

  /// Default max width for centered dialogs / detail sheets.
  static const double dialogMax = 520;

  /// Wide dialog cap (command palette, rich pickers).
  static const double dialogWide = 560;

  /// Reading column for long-form content (chat panes, article bodies).
  static const double readingColumn = 960;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < expanded;
  static bool isExpanded(double width) => width >= expanded && width < large;
  static bool isDesktop(double width) => width >= large;
}
