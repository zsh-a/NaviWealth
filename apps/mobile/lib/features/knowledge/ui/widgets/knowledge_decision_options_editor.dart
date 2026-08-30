import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_models.dart';

const int kKnowledgeDecisionPreferredOptionLimit = 3;

/// Owns the editable option fields and the one selected option.
///
/// The persisted model already supports multiple [DecisionOption] values. This
/// controller keeps that invariant explicit in every capture/edit surface:
/// labels are unique and non-empty, and the selected label always comes from
/// the current option list.
class KnowledgeDecisionOptionsController extends ChangeNotifier {
  KnowledgeDecisionOptionsController({
    Iterable<DecisionOption> options = const <DecisionOption>[],
    String? selectedLabel,
  }) {
    final seeded = options.toList(growable: true);
    final selected = selectedLabel?.trim() ?? '';
    if (seeded.isEmpty) {
      seeded.add(DecisionOption(label: selected));
    } else if (selected.isNotEmpty &&
        !seeded.any((option) => option.label.trim() == selected)) {
      seeded.insert(0, DecisionOption(label: selected));
    }
    for (final option in seeded) {
      _fields.add(_OptionFields.fromOption(option, _notifyChanged));
    }
    final selectedIndex = _fields.indexWhere(
      (fields) => fields.label.text.trim() == selected,
    );
    _selectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
  }

  final List<_OptionFields> _fields = <_OptionFields>[];
  final List<_OptionFields> _retired = <_OptionFields>[];
  var _selectedIndex = 0;
  var _disposed = false;

  int get length => _fields.length;
  int get selectedIndex => _selectedIndex;
  bool get canAdd => length < kKnowledgeDecisionPreferredOptionLimit;
  bool get canRemove => length > 1;

  bool get isValid {
    if (_fields.isEmpty ||
        _selectedIndex < 0 ||
        _selectedIndex >= _fields.length) {
      return false;
    }
    final values = options;
    return hasValidDecisionOptions(
      values,
      selectedLabel: values[_selectedIndex].label,
    );
  }

  String get selectedLabel =>
      isValid ? _fields[_selectedIndex].label.text.trim() : '';

  List<DecisionOption> get options => canonicalizeDecisionOptions(
    _fields.map((fields) {
      final rationale = fields.rationale.text.trim();
      return DecisionOption(
        label: fields.label.text.trim(),
        rationale: rationale.isEmpty ? null : rationale,
      );
    }),
  );

  void addOption() {
    if (!canAdd) return;
    _fields.add(_OptionFields.empty(_notifyChanged));
    _notifyChanged();
  }

  void removeAt(int index) {
    if (!canRemove || index < 0 || index >= _fields.length) return;
    _retired.add(_fields.removeAt(index));
    if (_selectedIndex > index) {
      _selectedIndex--;
    } else if (_selectedIndex == index) {
      _selectedIndex = index.clamp(0, _fields.length - 1);
    }
    _notifyChanged();
  }

  void select(int index) {
    if (index < 0 || index >= _fields.length || _selectedIndex == index) return;
    _selectedIndex = index;
    _notifyChanged();
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final fields in <_OptionFields>[..._fields, ..._retired]) {
      fields.dispose(_notifyChanged);
    }
    _fields.clear();
    _retired.clear();
    super.dispose();
  }
}

class _OptionFields {
  _OptionFields({required this.label, required this.rationale});

  factory _OptionFields.empty(VoidCallback listener) =>
      _OptionFields.fromOption(DecisionOption(label: ''), listener);

  factory _OptionFields.fromOption(
    DecisionOption option,
    VoidCallback listener,
  ) {
    final fields = _OptionFields(
      label: TextEditingController(text: option.label),
      rationale: TextEditingController(text: option.rationale),
    );
    fields.label.addListener(listener);
    fields.rationale.addListener(listener);
    return fields;
  }

  final TextEditingController label;
  final TextEditingController rationale;

  void dispose(VoidCallback listener) {
    label
      ..removeListener(listener)
      ..dispose();
    rationale
      ..removeListener(listener)
      ..dispose();
  }
}

class KnowledgeDecisionOptionsEditor extends StatelessWidget {
  const KnowledgeDecisionOptionsEditor({
    super.key,
    required this.controller,
    required this.keyPrefix,
    this.enabled = true,
  });

  final KnowledgeDecisionOptionsController controller;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AppSection.item(
          title: l10n.knowledgeDecisionOptionsLabel,
          children: [
            Text(
              l10n.knowledgeDecisionOptionsDescription,
              style: context.bodyCaptionStyle,
            ),
            const SizedBox(height: AppSpacing.s10),
            for (var index = 0; index < controller.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.s10),
              _DecisionOptionCard(
                key: ValueKey<String>('$keyPrefix-option-$index'),
                fields: controller._fields[index],
                index: index,
                keyPrefix: keyPrefix,
                selected: controller.selectedIndex == index,
                canRemove: controller.canRemove,
                enabled: enabled,
                onSelect: () => controller.select(index),
                onRemove: () => controller.removeAt(index),
              ),
            ],
            if (controller.canAdd) ...[
              const SizedBox(height: AppSpacing.s10),
              SizedBox(
                width: double.infinity,
                child: AppQuietButton(
                  key: ValueKey<String>('$keyPrefix-add'),
                  label: l10n.knowledgeDecisionAddOption,
                  prefix: const Icon(FLucideIcons.plus),
                  onPress: enabled ? controller.addOption : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DecisionOptionCard extends StatelessWidget {
  const _DecisionOptionCard({
    super.key,
    required this.fields,
    required this.index,
    required this.keyPrefix,
    required this.selected,
    required this.canRemove,
    required this.enabled,
    required this.onSelect,
    required this.onRemove,
  });

  final _OptionFields fields;
  final int index;
  final String keyPrefix;
  final bool selected;
  final bool canRemove;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FRadio(
                key: ValueKey<String>('$keyPrefix-select-$index'),
                value: selected,
                onChange: enabled ? (_) => onSelect() : null,
                semanticsLabel: l10n.knowledgeDecisionSelectOption(index + 1),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  selected
                      ? l10n.knowledgeDecisionOptionSelected
                      : l10n.knowledgeDecisionSelectOption(index + 1),
                  style: selected
                      ? context.captionLabelStyle.copyWith(
                          color: context.theme.colors.primary,
                        )
                      : context.captionMediumStyle,
                ),
              ),
              if (canRemove)
                FTooltip(
                  tipBuilder: (_, _) =>
                      Text(l10n.knowledgeDecisionRemoveOption),
                  child: FButton.icon(
                    key: ValueKey<String>('$keyPrefix-remove-$index'),
                    variant: FButtonVariant.ghost,
                    onPress: enabled ? onRemove : null,
                    child: const Icon(FLucideIcons.trash2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          FTextField(
            key: ValueKey<String>('$keyPrefix-label-$index'),
            control: FTextFieldControl.managed(controller: fields.label),
            enabled: enabled,
            label: Text(l10n.knowledgeDecisionOptionLabel(index + 1)),
          ),
          const SizedBox(height: AppSpacing.s8),
          FTextField(
            key: ValueKey<String>('$keyPrefix-rationale-$index'),
            control: FTextFieldControl.managed(controller: fields.rationale),
            enabled: enabled,
            label: Text(l10n.knowledgeDecisionOptionRationaleLabel),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
