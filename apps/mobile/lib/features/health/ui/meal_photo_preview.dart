import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/meal_photo_saver.dart';
import '../domain/meal_photo.dart';

class MealPhotoPreview extends ConsumerStatefulWidget {
  const MealPhotoPreview({super.key, required this.photo});

  final MealPhoto photo;

  @override
  ConsumerState<MealPhotoPreview> createState() => _MealPhotoPreviewState();
}

class _MealPhotoPreviewState extends ConsumerState<MealPhotoPreview> {
  bool _saving = false;
  bool _saved = false;
  MealPhotoSaveFailure? _failure;

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await ref.read(mealPhotoSaverProvider).save(widget.photo.bytes);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failure = error is MealPhotoSaveException
              ? error.failure
              : MealPhotoSaveFailure.failed;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(
              widget.photo.bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text(l.healthMealPhotoFailed),
            ),
          ),
        ),
        if (ref.watch(mealPhotoSaverProvider).supported) ...[
          const SizedBox(height: AppSpacing.s16),
          if (_failure case final failure?) ...[
            AppStatusBanner(
              kind: AppStatusKind.error,
              message: switch (failure) {
                MealPhotoSaveFailure.permissionDenied =>
                  l.healthMealPhotoSaveDenied,
                MealPhotoSaveFailure.insufficientSpace =>
                  l.healthMealPhotoSaveNoSpace,
                MealPhotoSaveFailure.failed => l.healthMealPhotoSaveFailed,
              },
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          if (_saved)
            AppStatusBanner(
              kind: AppStatusKind.success,
              message: l.healthMealPhotoSaved,
            )
          else
            AppBusyButton(
              buttonKey: const Key('meal-photo-save'),
              variant: FButtonVariant.outline,
              label: l.healthMealPhotoSave,
              busyLabel: l.healthMealPhotoSaving,
              prefix: const Icon(FLucideIcons.download),
              busy: _saving,
              onPress: _saving ? null : _save,
            ),
        ],
      ],
    );
  }
}
