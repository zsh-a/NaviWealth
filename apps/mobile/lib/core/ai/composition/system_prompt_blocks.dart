/// Domain-aware system prompt composition seam
/// (`docs/lifeos-shell.md` §4).
///
/// Each active LifeOS domain contributes one string block, appended
/// verbatim onto [kDeviceSystemPromptBase] by [composeDeviceSystemPrompt].
/// The shell ships the empty default so a domain-less build still
/// produces a usable prompt; `bootstrap.dart` overrides this provider
/// with the active-domain blocks, gated by `domainOptInsProvider` the
/// same way [deviceToolsProvider] is.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/device/device_system_prompt.dart';

/// Active LifeOS domains' system-prompt contributions.
final systemPromptBlocksProvider = Provider<List<String>>(
  (ref) => const <String>[],
);

/// Composed prompt = base + active domain blocks. The device runtime
/// reads this once per turn; toggling a domain on/off via opt-ins
/// flips the prompt on the next turn without restarting the app.
final assembledSystemPromptProvider = Provider<String>((ref) {
  final blocks = ref.watch(systemPromptBlocksProvider);
  return composeDeviceSystemPrompt(domainBlocks: blocks);
});
