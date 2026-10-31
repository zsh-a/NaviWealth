import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/meal_food_catalog.dart';
import '../domain/health_meal.dart';

Future<MealFood?> showMealFoodSheet(
  BuildContext context, {
  MealFood? initial,
}) => showGuardedFormSheet<MealFood>(
  context: context,
  builder: (_, dirty) => _MealFoodSheet(initial: initial, dirty: dirty),
);

class _MealFoodSheet extends StatefulWidget {
  const _MealFoodSheet({required this.initial, required this.dirty});
  final MealFood? initial;
  final FormDirtyController dirty;
  @override
  State<_MealFoodSheet> createState() => _MealFoodSheetState();
}

class _MealFoodSheetState extends State<_MealFoodSheet> {
  final _name = TextEditingController();
  final _grams = TextEditingController(text: '100');
  final _kcal = TextEditingController();
  final _protein = TextEditingController(text: '0');
  final _carbs = TextEditingController(text: '0');
  final _fat = TextEditingController(text: '0');
  String? _catalogId;
  String _source = 'manual';
  final _errors = <String, String>{};
  final _anchors = <String, GlobalKey>{
    for (final field in ['name', 'grams', 'kcal', 'protein', 'carbs', 'fat'])
      field: GlobalKey(),
  };
  late bool _showNutrition;
  bool _applying = false;
  bool _hasNutrientTotalError = false;
  late final _portionChanges = Listenable.merge([_grams, _kcal]);
  List<TextEditingController> get _all => [
    _name,
    _grams,
    _kcal,
    _protein,
    _carbs,
    _fat,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _showNutrition = false;
    if (initial != null) {
      _name.text = initial.name;
      _grams.text = '${initial.grams}';
      _setNutrients(initial.per100g);
      _catalogId = initial.catalogId;
      _source = initial.source;
    }
    widget.dirty.bindTextControllers(_all);
    for (final (index, controller) in _all.indexed) {
      var previousText = controller.text;
      controller.addListener(() {
        if (controller.text == previousText) return;
        previousText = controller.text;
        if (_applying) return;
        final field = _anchors.keys.elementAt(index);
        final clearsTotalError = index >= 3 && _hasNutrientTotalError;
        final changesSource =
            index != 1 && (_catalogId != null || _source != 'manual');
        if (!_errors.containsKey(field) &&
            !clearsTotalError &&
            !changesSource) {
          return;
        }
        setState(() {
          _errors.remove(field);
          if (index >= 3 && _hasNutrientTotalError) {
            _errors.remove('fat');
            _hasNutrientTotalError = false;
          }
          if (index != 1 && !_applying) {
            _catalogId = null;
            _source = 'manual';
          }
        });
      });
    }
  }

  void _setNutrients(MealNutrients n) {
    _kcal.text = '${n.kcal}';
    _protein.text = '${n.protein}';
    _carbs.text = '${n.carbs}';
    _fat.text = '${n.fat}';
  }

  @override
  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppSheet(
      title: widget.initial == null
          ? l.healthMealAddFood
          : l.healthMealEditFood,
      footer: AppSheetFooter(
        submitLabel: widget.initial == null
            ? l.healthMealAddFood
            : l.healthMealFoodSave,
        cancelLabel: l.commonCancel,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.initial == null) ...[
            _catalog(context),
            const SizedBox(height: AppSpacing.s16),
          ],
          SizedBox(
            key: _anchors['name'],
            child: FTextFormField(
              key: const Key('meal-food-name'),
              label: Text(l.healthMealFoodName),
              forceErrorText: _errors['name'],
              control: FTextFieldControl.managed(controller: _name),
              maxLength: 120,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _number(l.healthMealGrams, _grams, 'grams'),
          if (widget.initial == null) ...[
            const SizedBox(height: AppSpacing.s12),
            _number(l.healthMealEnergy, _kcal, 'kcal'),
          ],
          ListenableBuilder(
            listenable: _portionChanges,
            builder: (context, _) {
              final grams = _numberValue(_grams);
              final energy = _numberValue(_kcal);
              if (!(grams > 0 &&
                  grams <= 10000 &&
                  energy >= 0 &&
                  energy <= 1000)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s12),
                child: Text(
                  l.healthMealPortionKcal(
                    (grams * energy / 100).round().toString(),
                  ),
                  key: const Key('meal-food-portion-total'),
                  style: context.labelStyle,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          AppRevealControl(
            expanded: _showNutrition,
            collapsedLabel: l.healthMealNutritionDetails,
            expandedLabel: l.healthMealNutritionHide,
            onToggle: () => setState(() => _showNutrition = !_showNutrition),
          ),
          if (_showNutrition) ...[
            if (widget.initial != null) ...[
              _catalog(context),
              const SizedBox(height: AppSpacing.s12),
            ],
            Text(l.healthMealCatalogHint, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s16),
            Text(l.healthMealPer100g, style: context.labelStyle),
            const SizedBox(height: AppSpacing.s8),
            if (widget.initial != null) ...[
              _number(l.healthMealEnergy, _kcal, 'kcal'),
              const SizedBox(height: AppSpacing.s12),
            ],
            _number(l.healthMealProtein, _protein, 'protein'),
            const SizedBox(height: AppSpacing.s12),
            _number(l.healthMealCarbs, _carbs, 'carbs'),
            const SizedBox(height: AppSpacing.s12),
            _number(l.healthMealFat, _fat, 'fat'),
            const SizedBox(height: AppSpacing.s12),
            Text(
              _source == 'model_estimate'
                  ? l.healthMealModelEstimate
                  : _catalogId != null
                  ? '${l.healthMealCatalogSource} · $_catalogId'
                  : l.healthMealManualSource,
              style: context.microCaptionStyle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalog(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return FSelect<String>(
      key: ValueKey(_catalogId ?? 'custom'),
      label: Text(l.healthMealCatalog),
      items: {
        l.healthMealCustom: '',
        for (final food in mealFoodCatalog) food.label(language): food.id,
      },
      control: FSelectControl<String>.managed(
        initial: _catalogId ?? '',
        onChange: (id) {
          final food = mealCatalogFoodById(id);
          _applying = true;
          if (food != null) {
            _name.text = food.label(language);
            _setNutrients(food.per100g);
          }
          _applying = false;
          setState(() {
            _catalogId = food?.id;
            _source = food == null ? 'manual' : 'USDA FDC ${food.id}';
            _showNutrition = false;
            _errors.clear();
            _hasNutrientTotalError = false;
          });
          widget.dirty.markDirty();
        },
      ),
    );
  }

  Widget _number(
    String label,
    TextEditingController controller,
    String field,
  ) => SizedBox(
    key: _anchors[field],
    child: FTextFormField(
      key: Key('meal-food-$field'),
      label: Text(label),
      forceErrorText: _errors[field],
      control: FTextFieldControl.managed(controller: controller),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
    ),
  );

  double _numberValue(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ??
      double.nan;

  void _save() {
    final l = AppLocalizations.of(context);
    final food = MealFood(
      name: _name.text.trim(),
      grams: _numberValue(_grams),
      per100g: MealNutrients(
        kcal: _numberValue(_kcal),
        protein: _numberValue(_protein),
        carbs: _numberValue(_carbs),
        fat: _numberValue(_fat),
      ),
      source: _source,
      catalogId: _catalogId,
    );
    if (!food.isValid) {
      setState(() {
        _errors.clear();
        _hasNutrientTotalError = false;
        if (food.name.isEmpty || food.name.length > 120) {
          _errors['name'] = l.commonRequiredField;
        }
        if (!food.grams.isFinite || food.grams <= 0 || food.grams > 10000) {
          _errors['grams'] = l.healthMealGramsError;
        }
        final n = food.per100g;
        if (!n.kcal.isFinite || n.kcal < 0 || n.kcal > 1000) {
          _errors['kcal'] = l.healthMealEnergyError;
        }
        for (final (field, value) in [
          ('protein', n.protein),
          ('carbs', n.carbs),
          ('fat', n.fat),
        ]) {
          if (!value.isFinite || value < 0 || value > 100) {
            _errors[field] = l.healthMealNutrientError;
          }
        }
        if (n.protein + n.carbs + n.fat > 105 && !_errors.containsKey('fat')) {
          _errors['fat'] = l.healthMealNutrientTotalError;
          _hasNutrientTotalError = true;
        }
        if ((widget.initial != null && !n.validPer100g) ||
            ['protein', 'carbs', 'fat'].any(_errors.containsKey)) {
          _showNutrition = true;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _errors.isEmpty) return;
        final target = _anchors[_errors.keys.first]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: AppMotionPolicy.duration(context, Motion.componentChange),
            curve: Motion.standardDecelerate,
          );
        }
      });
      return;
    }
    widget.dirty.markPristine();
    Navigator.of(context).pop(food);
  }
}
