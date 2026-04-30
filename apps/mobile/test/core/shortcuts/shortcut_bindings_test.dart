import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shortcuts/shortcut_bindings.dart';
import 'package:naviwealth/core/shortcuts/shortcut_intents.dart';

void main() {
  group('globalShortcutBindings', () {
    final bindings = globalShortcutBindings();

    test('declares Cmd+K and Ctrl+K for the command palette', () {
      final paletteBindings = bindings
          .where((b) => b.intent is OpenCommandPaletteIntent)
          .toList();
      expect(paletteBindings, hasLength(2));
      final activators = paletteBindings
          .map((b) => b.activator)
          .cast<SingleActivator>();
      expect(
        activators.any((a) => a.meta && a.trigger == LogicalKeyboardKey.keyK),
        isTrue,
      );
      expect(
        activators.any(
          (a) => a.control && a.trigger == LogicalKeyboardKey.keyK,
        ),
        isTrue,
      );
    });

    test('declares Cmd+/ and Ctrl+/ for the help dialog', () {
      final helpBindings = bindings
          .where((b) => b.intent is ShowShortcutHelpIntent)
          .toList();
      expect(helpBindings, hasLength(2));
      final activators = helpBindings
          .map((b) => b.activator)
          .cast<SingleActivator>();
      expect(
        activators.any((a) => a.meta && a.trigger == LogicalKeyboardKey.slash),
        isTrue,
      );
      expect(
        activators.any(
          (a) => a.control && a.trigger == LogicalKeyboardKey.slash,
        ),
        isTrue,
      );
    });

    test('declares Esc for dismissing overlays', () {
      final escBindings = bindings
          .where((b) => b.intent is DismissOverlayIntent)
          .toList();
      expect(escBindings, hasLength(1));
      final activator = escBindings.single.activator as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.escape);
      expect(activator.meta, isFalse);
      expect(activator.control, isFalse);
    });

    test('declares 1-5 for primary tab switching, in order', () {
      final tabBindings = bindings
          .where((b) => b.intent is SwitchPrimaryTabIntent)
          .toList();
      expect(tabBindings, hasLength(kPrimaryTabCount));
      final keys = <LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ];
      for (var i = 0; i < kPrimaryTabCount; i++) {
        final binding = tabBindings[i];
        expect(
          (binding.intent as SwitchPrimaryTabIntent).index,
          i,
          reason: 'binding $i should target tab index $i',
        );
        expect(
          (binding.activator as SingleActivator).trigger,
          keys[i],
          reason: 'binding $i should be triggered by ${keys[i]}',
        );
      }
    });
  });

  test('globalShortcutMap collapses duplicate activators', () {
    // Sanity: meta and control variants are distinct activators, so the map
    // size equals the binding list size.
    final map = globalShortcutMap();
    expect(map.length, globalShortcutBindings().length);
  });
}
