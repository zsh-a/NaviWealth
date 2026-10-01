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
        final fragment = RegExp(r'[^,，\r\n]+$').firstMatch(value.text);
        final prefix = fragment?.group(0)?.trim().toLowerCase() ?? '';
        final suggestions = available
            .where(
              (tag) =>
                  !selected.contains(tag) &&
                  tag.toLowerCase().startsWith(prefix),
            )
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
              Wrap(
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s4,
                children: [
                  for (final tag in selected)
                    AppFilterChip(
                      key: ValueKey('knowledge-tag-remove-$tag'),
                      label: tag,
                      active: true,
                      onPress: null,
                      onClear: enabled
                          ? () => _setTags(
                              selected.where((value) => value != tag),
                            )
                          : null,
                      clearSemanticLabel: '${l10n.commonDelete}: $tag',
                    ),
                ],
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s4,
                children: [
                  for (final tag in suggestions)
                    AppFilterChip(
                      key: ValueKey('knowledge-tag-suggestion-$tag'),
                      label: tag,
                      active: false,
                      onPress: enabled
                          ? () {
                              final completed = fragment == null
                                  ? selected
                                  : parseKnowledgeTags(
                                      value.text.substring(0, fragment.start),
                                    );
                              _setTags([...completed, tag]);
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

  void _setTags(Iterable<String> tags) {
    final values = tags.toSet().toList();
    final text = values.isEmpty ? '' : '${values.join(', ')}, ';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
