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
import '../domain/health_meal.dart';
import 'health_meal_summary.dart';
import 'meal_food_sheet.dart';

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
  HealthMeal? _initial;
  late final String? _owner;
  late DateTime _capturedAt;
  late DateTime _day;
  HealthMealType _type = HealthMealType.lunch;
  Uint8List? _photo;
  bool _photoChanged = false;
  bool _removePhoto = false;
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
      final photo = meal == null
          ? null
          : await repo.photo(id: meal.id, ownerUserId: owner!);
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
          _recognitionModel = meal.recognitionModel;
          _photo = photo;
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
    _capturedAt = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
      time.second,
    );
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
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(widget.mealId == null ? l.healthMealNew : l.healthMealEdit),
        confirmLeave: handleBackIntent,
        child: AppFormScaffoldBody(
          onSubmit: editable && !_busy ? _save : null,
          action: AppBusyButton(
            buttonKey: const Key('meal-save'),
            label: l.commonSave,
            busy: _saving,
            onPress: editable && !_working ? _save : null,
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
              FButton(onPress: _load, child: Text(l.commonRetry)),
            ] else ...[
              Text(l.healthMealPhoto, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s8),
              if (_photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.memory(
                    _photo!,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(l.healthMealPhotoFailed),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: _busy ? null : () => _capture(camera: true),
                    child: Text(l.healthMealCamera),
                  ),
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: _busy ? null : () => _capture(camera: false),
                    child: Text(l.healthMealGallery),
                  ),
                  if (_photo != null)
                    FButton(
                      variant: FButtonVariant.ghost,
                      mainAxisSize: MainAxisSize.min,
                      onPress: _busy
                          ? null
                          : () {
                              setState(() {
                                _photo = null;
                                _photoChanged = true;
                                _removePhoto = true;
                              });
                              dirty.markDirty();
                            },
                      child: Text(l.healthMealRemovePhoto),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(l.healthMealPhotoLocal, style: context.microCaptionStyle),
              const SizedBox(height: AppSpacing.s12),
              AppBusyButton(
                buttonKey: const Key('meal-recognize'),
                label: l.healthMealRecognize,
                busyLabel: l.healthMealRecognizing,
                busy: _working,
                variant: FButtonVariant.outline,
                onPress: _photo == null || _saving || client == null
                    ? null
                    : _recognize,
              ),
              if (client == null) ...[
                const SizedBox(height: AppSpacing.s8),
                Text(l.healthMealModelRequired, style: context.captionStyle),
              ],
              const SizedBox(height: AppSpacing.s20),
              FDateField.calendar(
                key: ValueKey(_day),
                label: Text(l.commonDate),
                enabled: !_busy,
                clearable: false,
                selectionControl: FDateSelectionControl.managedSingle(
                  initial: _day,
                  onChange: (day) {
                    if (day == null || _busy) return;
                    setState(() {
                      _day = DateTime.utc(day.year, day.month, day.day);
                      _setCaptureDay(_day);
                    });
                    dirty.markDirty();
                  },
                ),
                calendar: FDateFieldGridCalendarProperties(
                  control: FGridCalendarControl(
                    start: DateTime.utc(1970),
                    end: today.add(const Duration(days: 1)),
                    today: today,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              SegmentedRow<HealthMealType>(
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
              Text(l.healthMealFoods, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s8),
              for (final (index, food) in _foods.indexed) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
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
                            ? '${l.healthMealCatalogSource} · ${food.catalogId}'
                            : l.healthMealManualSource,
                        style: context.microCaptionStyle,
                      ),
                      Wrap(
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s4,
                        children: [
                          FButton(
                            variant: FButtonVariant.ghost,
                            mainAxisSize: MainAxisSize.min,
                            onPress: _busy ? null : () => _editFood(index),
                            child: Text(l.healthMealEditFood),
                          ),
                          FButton(
                            variant: FButtonVariant.ghost,
                            mainAxisSize: MainAxisSize.min,
                            onPress: _busy
                                ? null
                                : () {
                                    setState(() => _foods.removeAt(index));
                                    dirty.markDirty();
                                  },
                            child: Text(l.healthMealRemoveFood),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const AppGroupedDivider(),
              ],
              const SizedBox(height: AppSpacing.s8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: _busy || _foods.length >= 30
                    ? null
                    : () => _editFood(null),
                child: Text(l.healthMealAddFood),
              ),
              if (_foods.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                HealthMealTotals(
                  total: _foods.fold(
                    MealNutrients.zero,
                    (sum, food) => sum + food.nutrients,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s12),
              Text(l.healthMealEstimateHint, style: context.captionStyle),
              const SizedBox(height: AppSpacing.s16),
              FTextFormField(
                label: Text(l.commonNote),
                enabled: !_busy,
                maxLength: 1000,
                maxLines: 3,
                control: FTextFieldControl.managed(controller: _note),
              ),
              if (_initial != null) ...[
                const SizedBox(height: AppSpacing.s20),
                AppBusyButton(
                  label: l.commonDelete,
                  variant: FButtonVariant.destructive,
                  onPress: _busy ? null : _delete,
                ),
              ],
              if (_error != null || submissionFailureMessage != null) ...[
                const SizedBox(height: AppSpacing.s12),
                AppStatusBanner(
                  kind: AppStatusKind.error,
                  message: _error ?? submissionFailureMessage!,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _capture({required bool camera}) async {
    if (_busy || !_sessionValid) return;
    setState(() {
      _working = true;
      _error = null;
    });
    dirty.busy = true;
    try {
      final bytes = await ref
          .read(mealPhotoCaptureProvider)
          .pick(camera: camera);
      if (!mounted || !_sessionValid || bytes == null) return;
      setState(() {
        _photo = bytes;
        _photoChanged = true;
        _removePhoto = false;
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

  Future<void> _recognize() async {
    final photo = _photo;
    final client = ref.read(mealRecognitionClientProvider);
    if (_busy || !_sessionValid || photo == null || client == null) return;
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
      });
      final result = await client.recognize(
        photoBytes: photo,
        languageCode: language,
        allowUpload: true,
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
    } catch (_) {
      if (mounted) setState(() => _error = l.healthMealRecognitionFailed);
    } finally {
      dirty.busy = false;
      if (mounted) {
        setState(() {
          _working = false;
          _confirming = false;
        });
      }
    }
  }

  Future<void> _editFood(int? index) async {
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
  }

  Future<void> _save() async {
    if (_busy || !_sessionValid) return;
    final l = AppLocalizations.of(context);
    if (_foods.isEmpty) {
      setState(() => _error = l.healthMealNeedFood);
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
          photoBytes: _photoChanged ? _photo : null,
          removePhoto: _removePhoto,
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
