/// Three-tier responsive breakpoints used across the app.
///
/// Defines mobile / tablet / desktop layouts.
/// Tokens live here so individual widgets agree on the same widths.
class Breakpoints {
  const Breakpoints._();

  /// `< mobile` is single-column mobile.
  static const double mobile = 600;

  /// Window width at which the application shell expands its compact rail
  /// into the full desktop sidebar. Shell chrome must use this token against
  /// the total viewport width so nested navigation rails do not shift the
  /// breakpoint.
  static const double shellDesktop = 1280;

  /// `mobile..desktop` is the tablet range for content-owned layouts.
  ///
  /// Shell-owned layouts must use [shellDesktop] explicitly so shell chrome
  /// can evolve without shifting content breakpoints.
  static const double desktop = 1240;

  /// Threshold (measured against a *surface's* own constraints, not the
  /// window) at which content frames flip from a stacked column to a
  /// two-column layout. Smaller than [desktop] because the shell already
  /// reserves space for navigation chrome — a 1240-window minus a
  /// ~256-wide drawer leaves ~984 dp for content, which stays single-column.
  static const double contentTwoColumn = 1024;

  /// Threshold at which content frames switch from 2-column to 3-column grids.
  /// Used by health metric grids and similar dense layouts.
  static const double contentThreeColumn = 720;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}
