part of '_widgets.dart';

/// A single tile in the knowledge type picker grid.
///
/// Shows an icon chip + label. When [highlighted] is true, the tile gets
/// a primary-color border to indicate it matches the active Library segment.
class KnowledgeCreateTile extends StatelessWidget {
  const KnowledgeCreateTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      level: SoftCardLevel.raised,
      onPress: onPress,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconTile(
            icon: icon,
            color: colors.primary,
            size: AppSpacing.s40,
            iconSize: AppIconSizes.md,
            radius: AppRadius.sm,
            backgroundOpacity: highlighted
                ? AppOpacity.light
                : AppOpacity.subtle,
            foregroundOpacity: 1,
          ),
          const SizedBox(height: AppPageRhythm.row),
          Text(
            label,
            style: context.captionLabelStyle.copyWith(
              color: highlighted ? colors.primary : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// One entry in the knowledge type picker: icon, label, and a callback
/// that opens the corresponding writer sheet.
class KnowledgeCreateOption {
  const KnowledgeCreateOption({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

/// Opens a bottom sheet with a 2-column grid of knowledge types.
///
/// The caller provides [options] (one per knowledge type) and optionally
/// [activeLabel] to highlight the tile matching the current Library segment.
/// When a tile is tapped the sheet closes and the option's [onSelected]
/// callback fires — typically opening the corresponding writer sheet.
Future<void> showKnowledgeCreateSheet(
  BuildContext context, {
  required List<KnowledgeCreateOption> options,
  String? activeLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  final selected = await showAppSheet<String>(
    context: context,
    title: l10n.knowledgeCreateEntry,
    subtitle: l10n.knowledgeNewChooserSubtitle,
    builder: (sheetContext) {
      final width = MediaQuery.sizeOf(sheetContext).width;
      final cols = width >= Breakpoints.compactContent ? 2 : 1;
      const gap = AppSpacing.s8;
      final itemWidth = cols == 1
          ? width
          : (width - AppSpacing.s16 * 2 - gap) / 2;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s16),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in options)
              SizedBox(
                width: itemWidth,
                child: KnowledgeCreateTile(
                  icon: option.icon,
                  label: option.label,
                  highlighted: option.label == activeLabel,
                  onPress: () => Navigator.of(sheetContext).pop(option.label),
                ),
              ),
          ],
        ),
      );
    },
  );
  if (selected == null) return;
  final match = options.where((o) => o.label == selected);
  if (match.isNotEmpty) {
    match.first.onSelected();
  }
}
