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
    return AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, photo) in photos.indexed) ...[
            if (index > 0) const AppGroupedDivider(),
            Padding(
              key: ValueKey('meal-view-$index'),
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTappable(
                    key: ValueKey('meal-view-preview-$index'),
                    semanticsLabel: l.healthMealPreview,
                    onPress: () => showAppSheet<void>(
                      context: context,
                      title: mealPhotoRoleLabel(l, photo.role),
                      builder: (_) => MealPhotoPreview(photo: photo),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Image.memory(
                        photo.bytes,
                        width: AppSpacing.s64,
                        height: AppSpacing.s64 + AppSpacing.s16,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: AppSpacing.s64,
                          height: AppSpacing.s64 + AppSpacing.s16,
                          child: Icon(FLucideIcons.imageOff),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FSelect<MealPhotoRole>(
                          key: ValueKey(
                            'meal-view-role-$index-${photo.role.name}',
                          ),
                          enabled: onRoleChanged != null,
                          label: Text(l.healthMealPhotoRole),
                          items: {
                            for (final role in MealPhotoRole.values)
                              mealPhotoRoleLabel(l, role): role,
                          },
                          control: FSelectControl<MealPhotoRole>.managed(
                            initial: photo.role,
                            onChange: (role) {
                              if (role != null) {
                                onRoleChanged?.call(index, role);
                              }
                            },
                          ),
                        ),
                        if (photo.timestampMs case final int time) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            l.healthMealVideoFrame(
                              (time / 1000).toStringAsFixed(1),
                            ),
                            style: context.microCaptionStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppIconButton(
                    key: ValueKey('meal-view-remove-$index'),
                    icon: FLucideIcons.x,
                    tooltip: l.healthMealRemovePhoto,
                    onPress: onRemove == null ? null : () => onRemove!(index),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
