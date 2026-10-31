import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/meal_photo.dart';
import 'meal_photo_preview.dart';

String mealPhotoRoleLabel(AppLocalizations l, MealPhotoRole role) =>
    switch (role) {
      MealPhotoRole.overview => l.healthMealViewOverview,
      MealPhotoRole.side => l.healthMealViewSide,
      MealPhotoRole.detail => l.healthMealViewDetail,
      MealPhotoRole.label => l.healthMealViewLabel,
      MealPhotoRole.afterMeal => l.healthMealViewAfter,
    };

class MealPhotoList extends StatelessWidget {
  const MealPhotoList({
    super.key,
    required this.photos,
    required this.onRoleChanged,
    required this.onRemove,
  });
  final List<MealPhoto> photos;
  final void Function(int index, MealPhotoRole role)? onRoleChanged;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, photo) in photos.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.s8),
            SizedBox(
              key: ValueKey('meal-view-$index'),
              width: AppSpacing.s64 + AppSpacing.s40,
              child: AppTappable(
                key: ValueKey('meal-view-preview-$index'),
                semanticsLabel:
                    '${l.healthMealPreview} ${index + 1} · ${mealPhotoRoleLabel(l, photo.role)}',
                borderRadius: BorderRadius.circular(AppRadius.md),
                onPress: () => _preview(context, index, photo),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(
                        photo.bytes,
                        width: AppSpacing.s64 + AppSpacing.s40,
                        height: AppSpacing.s64 + AppSpacing.s16,
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                        errorBuilder: (_, _, _) => SizedBox(
                          height: AppSpacing.s64 + AppSpacing.s16,
                          child: ColoredBox(
                            color: context.theme.colors.muted,
                            child: const Icon(FLucideIcons.imageOff),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s8,
                        horizontal: AppSpacing.s4,
                      ),
                      child: Text(
                        mealPhotoRoleLabel(l, photo.role),
                        style: context.microCaptionStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context, int index, MealPhoto photo) =>
      showAppSheet<void>(
        context: context,
        title: AppLocalizations.of(context).healthMealPreview,
        builder: (sheetContext) {
          final l = AppLocalizations.of(sheetContext);
          var role = photo.role;
          return StatefulBuilder(
            builder: (context, setState) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MealPhotoPreview(photo: photo),
                const SizedBox(height: AppSpacing.s16),
                FSelect<MealPhotoRole>(
                  key: ValueKey('meal-view-role-$index-${role.name}'),
                  enabled: onRoleChanged != null,
                  label: Text(l.healthMealPhotoRole),
                  items: {
                    for (final role in MealPhotoRole.values)
                      mealPhotoRoleLabel(l, role): role,
                  },
                  control: FSelectControl<MealPhotoRole>.managed(
                    initial: role,
                    onChange: (value) {
                      if (value == null || onRoleChanged == null) return;
                      onRoleChanged!(index, value);
                      setState(() => role = value);
                    },
                  ),
                ),
                if (photo.timestampMs case final int time) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    l.healthMealVideoFrame((time / 1000).toStringAsFixed(1)),
                    style: context.microCaptionStyle,
                  ),
                ],
                if (onRemove != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppQuietButton(
                    key: ValueKey('meal-view-remove-$index'),
                    label: l.healthMealRemovePhoto,
                    prefix: const Icon(FLucideIcons.trash2),
                    tone: AppQuietButtonTone.danger,
                    onPress: () {
                      Navigator.of(sheetContext).pop();
                      onRemove!(index);
                    },
                  ),
                ],
              ],
            ),
          );
        },
      );
}
