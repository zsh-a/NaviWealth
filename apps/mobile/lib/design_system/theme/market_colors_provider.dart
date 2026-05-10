import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../preferences/theme_preferences.dart';
import 'market_colors.dart';

/// Active brightness, watched by [marketColorsProvider]. Flipped from
/// `app.dart` whenever the resolved Material/Forui brightness changes.
final brightnessProvider = StateProvider<Brightness>((_) => Brightness.light);

/// Resolves the user's [MarketColorMode] preference + the active brightness
/// into a concrete [MarketColors] token set. Watched at the app root and
/// installed into the tree as a [MarketColorsScope].
final marketColorsProvider = Provider<MarketColors>((ref) {
  final mode = ref.watch(marketColorModeProvider);
  final brightness = ref.watch(brightnessProvider);
  return MarketColors.fromMode(mode, brightness: brightness);
});
