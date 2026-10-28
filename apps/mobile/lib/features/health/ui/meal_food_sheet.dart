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
  String? _error;
  bool _applying = false;
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
    if (initial != null) {
      _name.text = initial.name;
      _grams.text = '${initial.grams}';
      _setNutrients(initial.per100g);
      _catalogId = initial.catalogId;
      _source = initial.source;
    }
    widget.dirty.bindTextControllers(_all);
    for (final controller in [_name, _kcal, _protein, _carbs, _fat]) {
      controller.addListener(_nutritionEdited);
    }
  }

  void _setNutrients(MealNutrients n) {
    _kcal.text = '${n.kcal}';
    _protein.text = '${n.protein}';
    _carbs.text = '${n.carbs}';
    _fat.text = '${n.fat}';
  }

  void _nutritionEdited() {
    if (_applying) return;
    setState(() {
      _catalogId = null;
      _source = 'manual';
      _error = null;
    });
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
    final language = Localizations.localeOf(context).languageCode;
    return AppSheet(
      title: widget.initial == null
          ? l.healthMealAddFood
          : l.healthMealEditFood,
      footer: AppSheetFooter(
        submitLabel: l.commonSave,
        cancelLabel: l.commonCancel,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FSelect<String>(
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
                  _error = null;
                });
                widget.dirty.markDirty();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(l.healthMealCatalogHint, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            key: const Key('meal-food-name'),
            label: Text(l.healthMealFoodName),
            control: FTextFieldControl.managed(controller: _name),
            maxLength: 120,
          ),
          const SizedBox(height: AppSpacing.s12),
          _number(l.healthMealGrams, _grams, 'meal-food-grams'),
          const SizedBox(height: AppSpacing.s16),
          Text(l.healthMealPer100g, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          _number(l.healthMealEnergy, _kcal, 'meal-food-kcal'),
          const SizedBox(height: AppSpacing.s12),
          _number(l.healthMealProtein, _protein, 'meal-food-protein'),
          const SizedBox(height: AppSpacing.s12),
          _number(l.healthMealCarbs, _carbs, 'meal-food-carbs'),
          const SizedBox(height: AppSpacing.s12),
          _number(l.healthMealFat, _fat, 'meal-food-fat'),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _number(String label, TextEditingController controller, String key) =>
      FTextFormField(
        key: Key(key),
        label: Text(label),
        control: FTextFieldControl.managed(controller: controller),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
      );

  void _save() {
    double number(TextEditingController c) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? double.nan;
    final food = MealFood(
      name: _name.text.trim(),
      grams: number(_grams),
      per100g: MealNutrients(
        kcal: number(_kcal),
        protein: number(_protein),
        carbs: number(_carbs),
        fat: number(_fat),
      ),
      source: _source,
      catalogId: _catalogId,
    );
    if (!food.isValid) {
      setState(
        () => _error = AppLocalizations.of(context).healthMealInvalidFood,
      );
      return;
    }
    widget.dirty.markPristine();
    Navigator.of(context).pop(food);
  }
}
