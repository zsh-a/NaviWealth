import 'package:flutter/widgets.dart';

/// Value object for a quick action on a domain AI entry surface (used by
/// KnowledgeOS's inbox assistant bar). The old `DomainAiPromptBar` widget
/// itself shipped with zero call sites and was removed (doc 15 §8) — the
/// tablet rail and floating dock now own the Ask-AI affordance.
class DomainAiPromptAction {
  const DomainAiPromptAction({
    required this.label,
    required this.icon,
    required this.onPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPress;
}
