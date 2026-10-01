import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

Future<String?> showKnowledgeTagPickerSheet({
  required BuildContext context,
  required List<String> tags,
  required String? selectedTag,
  required String title,
  required String allLabel,
}) => showAppSheet<String>(
  context: context,
  title: title,
  scrollable: false,
  builder: (_) =>
      _TagPicker(tags: tags, selectedTag: selectedTag, allLabel: allLabel),
);

class _TagPicker extends StatefulWidget {
  const _TagPicker({
    required this.tags,
    required this.selectedTag,
    required this.allLabel,
  });
  final List<String> tags;
  final String? selectedTag;
  final String allLabel;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = widget.tags
        .where((tag) => tag.toLowerCase().contains(_query))
        .toList();
    return SizedBox(
      height: AppControlHeights.searchSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            key: const Key('knowledge-tag-picker-search'),
            controller: _search,
            hint: l10n.knowledgeTagsSearchHint,
            clearLabel: l10n.aiChatSessionsSearchClear,
            onChanged: (query) =>
                setState(() => _query = query.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.s8),
          _row(null),
          const AppGroupedDivider(),
          Expanded(
            child: tags.isEmpty
                ? AppEmptyState(
                    icon: FLucideIcons.searchX,
                    title: l10n.knowledgeLibraryNoResultsTitle,
                    compact: true,
                  )
                : ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (_, index) => _row(tags[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(String? tag) => Semantics(
    selected: widget.selectedTag == tag,
    child: AppNavRow(
      key: ValueKey(
        tag == null
            ? 'knowledge-library-all-tags'
            : 'knowledge-library-tag-$tag',
      ),
      icon: FLucideIcons.tag,
      title: tag ?? widget.allLabel,
      titleMaxLines: 1,
      showChevron: false,
      trailing: widget.selectedTag == tag
          ? const Icon(FLucideIcons.check, size: AppIconSizes.sm)
          : null,
      onTap: () => Navigator.of(context).pop(tag ?? ''),
    ),
  );
}
