import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// Includes the app's keyboard-safe Forui button subclass.
extension AppButtonFinders on CommonFinders {
  Finder buttonWithText(String label) =>
      ancestor(of: text(label), matching: bySubtype<FButton>());
}
