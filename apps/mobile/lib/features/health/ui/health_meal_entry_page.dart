import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/health_meal_providers.dart';
import '../data/health_series_providers.dart';
import '../data/meal_photo_capture.dart';
import '../data/meal_recognition_client.dart';
import '../data/meal_video_frames.dart';
import '../domain/health_meal.dart';
import '../domain/meal_photo.dart';
import 'health_meal_summary.dart';
import 'meal_date_control.dart';
import 'meal_food_sheet.dart';
import 'meal_photo_list.dart';

class HealthMealEntryPage extends ConsumerStatefulWidget {
  const HealthMealEntryPage({super.key, this.mealId, this.initialDay});
  final String? mealId;
  final DateTime? initialDay;
  @override
  ConsumerState<HealthMealEntryPage> createState() =>
      _HealthMealEntryPageState();
}

class _HealthMealEntryPageState extends ConsumerState<HealthMealEntryPage>
    with
        FormDirtyGuard<HealthMealEntryPage>,
        FormSubmission<HealthMealEntryPage> {
  final _note = TextEditingController();
  final _foods = <MealFood>[];
  final _foodsAnchor = GlobalKey();
  bool _showDetails = false;
  HealthMeal? _initial;
  late final String? _owner;
  late DateTime _capturedAt;
  late DateTime _day;
  HealthMealType _type = HealthMealType.lunch;
  final _photos = <MealPhoto>[];
  bool _photosChanged = false;
  bool _recognizing = false;
  String? _recognitionModel;
  bool _loading = false;
  bool _working = false;
  bool _confirming = false;
  bool _saving = false;
  String? _error;
  bool get _busy => _working || _saving || _confirming;

  @override
  String get leaveFallback => HealthRoutes.meals;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(activeUserIdProvider);
    _capturedAt = ref.read(healthClockProvider)();
    final today = DateTime.utc(
      _capturedAt.year,
      _capturedAt.month,
      _capturedAt.day,
    );
    final requested = widget.initialDay;
    _day =
        requested != null && !requested.isAfter(today) && requested.year >= 1970
        ? DateTime.utc(requested.year, requested.month, requested.day)
        : today;
    if (_capturedAt.hour < 10) {
      _type = HealthMealType.breakfast;
    } else if (_capturedAt.hour >= 17) {
      _type = HealthMealType.dinner;
    }
    _setCaptureDay(_day);
    dirty.bindTextControllers([_note]);
    if (widget.mealId != null) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(healthMealRepositoryProvider.future);
      final owner = _owner;
      final meal = owner == null
          ? null
          : await repo.find(id: widget.mealId!, ownerUserId: owner);
      final photos = meal == null
          ? const <MealPhoto>[]
          : await repo.photos(id: meal.id, ownerUserId: owner!);
      if (!mounted || !_sessionValid) return;
      setState(() {
        _initial = meal;
        if (meal == null) {
          _error = AppLocalizations.of(context).healthMealNotFound;
        } else {
          _capturedAt = meal.capturedAt;
          _day = meal.day;
          _type = meal.type;
          _foods.addAll(meal.foods);
          _note.text = meal.note ?? '';
          _showDetails = _note.text.isNotEmpty;
          _recognitionModel = meal.recognitionModel;
          _photos.addAll(photos);
        }
        _loading = false;
      });
      dirty.markPristine();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).commonSaveFailed;
        });
      }
    }
  }

  bool get _sessionValid =>
      _owner != null &&
      ref.read(activeUserIdProvider) == _owner &&
      (ref
              .read(auth.domainOptInsProvider)
              .value
              ?.contains(DomainScope.health) ??
          false);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setCaptureDay(DateTime day) {
    final time = _capturedAt.toLocal();
    final candidate = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
      time.second,
    );
    final now = ref.read(healthClockProvider)();
    // Moving an older evening meal to today must not create a future instant.
    _capturedAt = candidate.isAfter(now) ? now : candidate;
  }

  void _changeMealDay(DateTime day) {
    final today = ref.read(healthCalendarDayProvider);
    if (_busy ||
        !_sessionValid ||
        day.year < 1970 ||
        day.isAfter(today) ||
        day == _day) {
      return;
    }
    setState(() {
      _day = DateTime.utc(day.year, day.month, day.day);
      _setCaptureDay(_day);
    });
    dirty.markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.watch(activeUserIdProvider);
    ref.watch(auth.domainOptInsProvider);
    final valid = _sessionValid;
    final today = ref.watch(healthCalendarDayProvider);
    final client = ref.watch(mealRecognitionClientProvider);
    final editable =
        valid && !_loading && (widget.mealId == null || _initial != null);
    final canSave = editable && !_busy && _foods.isNotEmpty;
    final canCapture = !_busy && _photos.length < MealPhoto.maxCount;
    final total = _foods.fold(
      MealNutrients.zero,
      (sum, food) => sum + food.nutrients,
    );
    final failure = _error ?? submissionFailureMessage;
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(widget.mealId == null ? l.healthMealNew : l.healthMealEdit),
        confirmLeave: handleBackIntent,
        child: AppFormScaffoldBody(
          onSubmit: canSave ? _save : null,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editable) ...[
                if (failure != null) ...[
                  AppStatusBanner(kind: AppStatusKind.error, message: failure),
                  const SizedBox(height: AppSpacing.s8),
                ],
                if (_foods.isEmpty)
                  Text(l.healthMealNeedFood, style: context.captionStyle)
                else
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.s12,
                    runSpacing: AppSpacing.s4,
                    children: [
                      Text(l.healthMealTotal, style: context.captionStyle),
                      Text(
                        l.healthMealKcal(total.kcal.round().toString()),
                        style: context.labelStyle,
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.s8),
              ],
              AppBusyButton(
                buttonKey: const Key('meal-save'),
                label: l.healthMealSave,
                busy: _saving,
                onPress: canSave ? _save : null,
              ),
            ],
          ),
          children: [
            if (!valid)
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: l.healthMealSessionChanged,
              )
            else if (_loading)
              const SkeletonBox(height: 200)
            else if (!editable) ...[
              AppStatusBanner(
                kind: AppStatusKind.error,
                message: _error ?? l.healthMealNotFound,
              ),
              AppActionButton(
                size: FButtonSizeVariant.md,
                onPress: _load,
                child: Text(l.commonRetry),
              ),
            ] else ...[
              MealDateControl(
                day: _day,
                today: today,
                onChanged: _busy ? null : _changeMealDay,
              ),
              const SizedBox(height: AppSpacing.s8),
              SegmentedRow<HealthMealType>.inline(
                options: HealthMealType.values,
                value: _type,
                labelOf: (type) => healthMealTypeLabel(l, type),
                onChanged: _busy
                    ? null
                    : (type) {
                        setState(() => _type = type);
                        dirty.markDirty();
                      },
              ),
              const SizedBox(height: AppSpacing.s20),
              AppActionButton(
                buttonKey: const Key('meal-camera'),
                variant: _photos.isEmpty && _foods.isEmpty
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                emphasis: AppButtonEmphasis.filled,
                prefix: const Icon(FLucideIcons.camera),
                hapticIntent: AppInteractionIntent.select,
                onPress: canCapture ? () => _capture(camera: true) : null,
                child: Text(l.healthMealCamera),
              ),
              const SizedBox(height: AppSpacing.s8),
              if (_photos.isNotEmpty) ...[
                MealPhotoList(
                  photos: _photos,
                  onRoleChanged: _busy
                      ? null
                      : (index, role) {
                          if (!_sessionValid || _busy) return;
                          setState(() {
                            _photos[index] = _photos[index].withRole(role);
                            _photosChanged = true;
                          });
                          dirty.markDirty();
                        },
                  onRemove: _busy
                      ? null
                      : (index) {
                          if (!_sessionValid || _busy) return;
                          setState(() {
                            _photos.removeAt(index);
                            _photosChanged = true;
                          });
                          dirty.markDirty();
                        },
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s4,
                children: [
                  AppQuietButton(
                    label: l.healthMealGallery,
                    prefix: const Icon(FLucideIcons.image),
                    onPress: canCapture ? () => _capture(camera: false) : null,
                  ),
                  AppQuietButton(
                    label: l.healthMealManualEntry,
                    prefix: const Icon(FLucideIcons.plus),
                    onPress: _busy || _foods.length >= 30
                        ? null
                        : () => _editFood(null),
                  ),
                ],
              ),
              Text(
                l.healthMealPhotoPrivacyHint,
                style: context.microCaptionStyle,
              ),
              AppRevealControl(
                expanded: _showDetails,
                collapsedLabel: l.healthMealDetails,
                expandedLabel: l.healthMealHideDetails,
                enabled: !_busy,
                onToggle: () => setState(() => _showDetails = !_showDetails),
              ),
              if (_showDetails) ...[
                FTextFormField(
                  key: const Key('meal-context'),
                  label: Text(l.healthMealContext),
                  enabled: !_busy,
                  maxLength: 1000,
                  maxLines: 3,
                  control: FTextFieldControl.managed(controller: _note),
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(l.healthMealViewsHint, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s8),
                Text(l.healthMealPhotoLocal, style: context.microCaptionStyle),
                if (ref.watch(mealPhotoCaptureProvider).supportsVideo)
                  AppQuietButton(
                    key: const Key('meal-video'),
                    label: l.healthMealVideo,
                    prefix: const Icon(FLucideIcons.video),
                    onPress: canCapture ? _captureVideo : null,
                  ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (_working && !_recognizing) ...[
                Text(l.healthMealPreparingImages, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s8),
              ],
              if (_photos.isNotEmpty) ...[
                if (client != null) ...[
                  if (!_photos.any((photo) => photo.isMealView)) ...[
                    Text(l.healthMealNeedMealView, style: context.captionStyle),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                  AppBusyButton(
                    buttonKey: const Key('meal-recognize'),
                    label: l.healthMealRecognize,
                    busyLabel: l.healthMealRecognizing,
                    busy: _recognizing,
                    emphasis: AppButtonEmphasis.filled,
                    variant: _foods.isEmpty
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    onPress: !_photos.any((photo) => photo.isMealView) || _busy
                        ? null
                        : _recognize,
                  ),
                ] else
                  Text(l.healthMealModelRequired, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s20),
              ],
              Column(
                key: _foodsAnchor,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.healthMealFoods, style: context.labelStyle),
                  if (_foods.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(l.healthMealReviewHint, style: context.captionStyle),
                  ],
                  const SizedBox(height: AppSpacing.s8),
                  for (final (index, food) in _foods.indexed) ...[
                    _foodRow(context, index, food),
                    const AppGroupedDivider(),
                  ],
                  const SizedBox(height: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.outline,
                    size: FButtonSizeVariant.md,
                    prefix: const Icon(FLucideIcons.plus),
                    hapticIntent: AppInteractionIntent.select,
                    onPress: _busy || _foods.length >= 30
                        ? null
                        : () => _editFood(null),
                    child: Text(l.healthMealAddFood),
                  ),
                  if (_foods.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s16),
                    HealthMealTotals(total: total),
                    const SizedBox(height: AppSpacing.s12),
                    Text(l.healthMealEstimateHint, style: context.captionStyle),
                  ],
                ],
              ),
              if (_initial != null) ...[
                const SizedBox(height: AppSpacing.s20),
                AppQuietButton(
                  label: l.commonDelete,
                  tone: AppQuietButtonTone.danger,
                  onPress: _busy ? null : _delete,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _foodRow(BuildContext context, int index, MealFood food) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: AppTappable(
            key: ValueKey('meal-food-$index'),
            semanticsLabel: '${l.healthMealEditFood}: ${food.name}',
            onPress: _busy ? null : () => _editFood(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(food.name, style: context.rowTitleStyle),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    '${food.grams.toStringAsFixed(0)} g · ${l.healthMealKcal(food.nutrients.kcal.round().toString())}',
                    style: context.captionStyle,
                  ),
                  Text(
                    food.isEstimate
                        ? l.healthMealModelEstimate
                        : food.catalogId != null
                        ? l.healthMealCatalogSource
                        : l.healthMealManualSource,
                    style: context.microCaptionStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
        AppIconButton(
          key: ValueKey('meal-food-actions-$index'),
          icon: FLucideIcons.ellipsis,
          tooltip: l.healthMealFoodActions,
          onPress: _busy ? null : () => _foodActions(index),
        ),
      ],
    );
  }

  Future<void> _foodActions(int index) async {
    final l = AppLocalizations.of(context);
    final action = await showAppSheet<String>(
      context: context,
      title: _foods[index].name,
      builder: (context) => AppActionSheetList(
        children: [
          AppActionSheetTile(
            icon: FLucideIcons.pencil,
            title: l.healthMealEditFood,
            onPress: () => Navigator.of(context).pop('edit'),
          ),
          AppActionSheetTile(
            icon: FLucideIcons.trash2,
            title: l.healthMealRemoveFood,
            destructive: true,
            onPress: () => Navigator.of(context).pop('remove'),
          ),
        ],
      ),
    );
    if (!mounted || !_sessionValid || _busy) return;
    if (action == 'edit') {
      await _editFood(index);
    } else if (action == 'remove') {
      setState(() => _foods.removeAt(index));
      dirty.markDirty();
    }
  }

  void _revealFoods() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _foodsAnchor.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: AppMotionPolicy.duration(context, Motion.componentChange),
        curve: Motion.standardDecelerate,
      );
    });
  }

  Future<void> _capture({required bool camera}) async {
    if (_busy || !_sessionValid || _photos.length >= MealPhoto.maxCount) return;
    setState(() {
      _working = true;
      _error = null;
    });
    dirty.busy = true;
    try {
      final capture = ref.read(mealPhotoCaptureProvider);
      final remaining = MealPhoto.maxCount - _photos.length;
      final images = camera
          ? [
              if (await capture.pick(camera: true) case final Uint8List bytes)
                bytes,
            ]
          : await capture.pickMany(limit: remaining);
      if (!mounted || !_sessionValid || images.isEmpty) return;
      if (images.length > remaining) {
        throw const FormatException('Too many views');
      }
      setState(() {
        _photos.addAll(images.map((bytes) => MealPhoto(bytes: bytes)));
        _photosChanged = true;
      });
      dirty.markDirty();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).healthMealPhotoFailed,
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _captureVideo() async {
    if (_busy || !_sessionValid || _photos.length >= MealPhoto.maxCount) return;
    final l = AppLocalizations.of(context);
    final camera = await showAppSheet<bool>(
      context: context,
      title: l.healthMealVideo,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.healthMealVideoHint, style: sheetContext.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          AppActionSheetList(
            children: [
              AppActionSheetTile(
                icon: FLucideIcons.video,
                title: l.healthMealVideoRecord,
                onPress: () => Navigator.of(sheetContext).pop(true),
              ),
              AppActionSheetTile(
                icon: FLucideIcons.folderOpen,
                title: l.healthMealVideoChoose,
                onPress: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || camera == null || !_sessionValid || _busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    dirty.busy = true;
    try {
      final remaining = MealPhoto.maxCount - _photos.length;
      final frames = await ref
          .read(mealPhotoCaptureProvider)
          .pickVideo(camera: camera, limit: remaining);
      if (!mounted || !_sessionValid || frames == null || frames.isEmpty) {
        return;
      }
      if (frames.length > remaining || frames.any((frame) => !frame.isValid)) {
        throw const MealVideoException('unreadable');
      }
      setState(() {
        _photos.addAll(frames);
        _photosChanged = true;
      });
      dirty.markDirty();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            MealVideoException(code: 'video_duration') =>
              l.healthMealVideoTooLong,
            MealVideoException(code: 'video_size') => l.healthMealVideoTooLarge,
            _ => l.healthMealVideoFailed,
          },
        );
      }
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _recognize() async {
    final photos = List<MealPhoto>.unmodifiable(_photos);
    final description = _note.text;
    final client = ref.read(mealRecognitionClientProvider);
    if (_busy ||
        !_sessionValid ||
        !photos.any((photo) => photo.isMealView) ||
        client == null) {
      return;
    }
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _confirming = true;
      _error = null;
    });
    dirty.busy = true;
    try {
      final allowed = await showConfirmDialog(
        context: context,
        title: Text(l.healthMealUploadTitle),
        body: Text(l.healthMealUploadBody(client.providerLabel)),
        confirmLabel: l.healthMealUploadAllow,
        cancelLabel: l.commonCancel,
      );
      if (!mounted ||
          allowed != true ||
          !_sessionValid ||
          !identical(client, ref.read(mealRecognitionClientProvider))) {
        return;
      }
      setState(() {
        _confirming = false;
        _working = true;
        _recognizing = true;
      });
      final result = await client.recognize(
        photos: photos,
        languageCode: language,
        allowUpload: true,
        context: description,
      );
      if (!mounted ||
          !_sessionValid ||
          !identical(client, ref.read(mealRecognitionClientProvider))) {
        return;
      }
      setState(() {
        _foods
          ..clear()
          ..addAll(result.foods);
        _recognitionModel = result.model;
      });
      dirty.markDirty();
      _revealFoods();
    } catch (_) {
      if (mounted) setState(() => _error = l.healthMealRecognitionFailed);
    } finally {
      dirty.busy = false;
      if (mounted) {
        setState(() {
          _working = false;
          _recognizing = false;
          _confirming = false;
        });
      }
    }
  }

  Future<void> _editFood(int? index) async {
    if (_busy || !_sessionValid) return;
    final food = await showMealFoodSheet(
      context,
      initial: index == null ? null : _foods[index],
    );
    if (!mounted || !_sessionValid || food == null) return;
    setState(() {
      if (index == null) {
        _foods.add(food);
      } else {
        _foods[index] = food;
      }
      _error = null;
    });
    dirty.markDirty();
    _revealFoods();
  }

  Future<void> _save() async {
    if (_busy || !_sessionValid) return;
    final l = AppLocalizations.of(context);
    if (_foods.isEmpty) {
      setState(() => _error = l.healthMealNeedFood);
      _revealFoods();
      return;
    }
    final foods = List<MealFood>.of(_foods);
    await submitFormAndLeave<HealthMeal>(
      dirty: dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      leaveFallback: leaveFallback,
      commit: () async {
        final repo = await ref.read(healthMealRepositoryProvider.future);
        if (!_sessionValid) throw StateError('Meal owner or domain changed');
        return repo.save(
          id: _initial?.id,
          expectedOwnerUserId: _owner!,
          expectedRevision: _initial?.sync.hlc,
          capturedAt: _capturedAt,
          day: _day,
          type: _type,
          foods: foods,
          note: _note.text,
          recognitionModel: _recognitionModel,
          photos: _photosChanged ? List<MealPhoto>.of(_photos) : null,
        );
      },
      failureMessage: (_) => l.commonSaveFailed,
      successMessage: l.commonSaved,
      tag: 'health-meal',
    );
  }

  Future<void> _delete() async {
    final meal = _initial;
    if (_busy || !_sessionValid || meal == null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l.commonDelete),
      body: Text(l.healthMealDeleteConfirm),
      confirmLabel: l.commonDelete,
      cancelLabel: l.commonCancel,
      destructive: true,
    );
    if (!mounted || confirmed != true || !_sessionValid || _busy) return;
    await submitFormAndLeave<void>(
      dirty: dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      leaveFallback: leaveFallback,
      commit: () async {
        final repo = await ref.read(healthMealRepositoryProvider.future);
        if (!_sessionValid) throw StateError('Meal owner or domain changed');
        await repo.delete(meal);
      },
      failureMessage: (_) => l.commonDeleteFailed,
      successMessage: l.commonDeleted,
      tag: 'health-meal-delete',
    );
  }
}
