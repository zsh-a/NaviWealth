import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/providers.dart';
import 'knowledge_tag_chips.dart';

/// Keeps the canonical tag text field while offering existing tags directly.
class KnowledgeTagInput extends ConsumerWidget {
  const KnowledgeTagInput({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final available =
        ref.watch(knowledgeLibraryTagsProvider).value ?? <String>[];
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final selected = parseKnowledgeTags(value.text);
        final suggestions = available
            .where((tag) => !selected.contains(tag))
            .take(6);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextField(
              control: FTextFieldControl.managed(controller: controller),
              enabled: enabled,
              label: Text(l10n.knowledgeNoteTagsLabel),
              hint: l10n.knowledgeNoteTagsHint,
            ),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              KnowledgeTagChips(tags: selected),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s4,
                children: [
                  for (final tag in suggestions)
                    AppFilterChip(
                      label: tag,
                      active: false,
                      onPress: enabled
                          ? () {
                              final text = [...selected, tag].join(', ');
                              controller.value = TextEditingValue(
                                text: text,
                                selection: TextSelection.collapsed(
                                  offset: text.length,
                                ),
                              );
                            }
                          : null,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
