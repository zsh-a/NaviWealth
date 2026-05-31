/// Three-tier responsive breakpoints used across the app.
///
/// Defines mobile / tablet / desktop layouts.
/// Tokens live here so individual widgets agree on the same widths.
class Breakpoints {
  const Breakpoints._();

  /// `< mobile` is single-column mobile.
  static const double mobile = 600;

  /// `mobile..desktop` is the tablet range.
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
