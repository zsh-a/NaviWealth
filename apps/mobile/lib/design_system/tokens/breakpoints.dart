/// Three-tier responsive breakpoints used across the app.
///
/// The parent epic (FIR-12) defines mobile / tablet / desktop layouts.
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

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}
