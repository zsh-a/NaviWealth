import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../../../core/ai/visual/visual.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import 'proposal_kind_labels.dart';

/// Inline edit sheet: lets the user override the high-frequency fields
/// (amount / price / note / date) before they confirm. Anything beyond
/// these flows back to the full entry pages — surfaced as a compact Forui
/// action at the bottom of the sheet.
class ProposalEditSheet extends ConsumerStatefulWidget {
  const ProposalEditSheet({super.key, required this.plan, this.initial});

  final ReadyProposalPlan plan;
  final Map<String, Object?>? initial;

  @override
  ConsumerState<ProposalEditSheet> createState() => _ProposalEditSheetState();
}

class _ProposalEditSheetState extends ConsumerState<ProposalEditSheet> {
  /// Lazy controller bag — populated as fields become visible. Keeping the
  /// values across mode toggles means typing in standard mode, flipping to
  /// full, and flipping back doesn't reset edits.
  final Map<String, TextEditingController> _controllers = {};
  List<ProposalKindEditField> _curated = const <ProposalKindEditField>[];
  bool _fullMode = false;
  bool _initialized = false;

  /// Payload keys that are bookkeeping rather than user content — never
  /// surface them in the editor.
  static const _internalKeys = <String>{'id', 'proposal_id', 'request_id'};

  void _ensureInitialized(AppLocalizations l10n) {
    if (_initialized) return;
    _initialized = true;
    final registry = ref.read(proposalKindRegistryProvider);
    _curated =
        registry.metaFor(widget.plan.kind)?.editableFields?.call(l10n) ??
        const <ProposalKindEditField>[];
    for (final field in _curated) {
      _controllers[field.payloadKey] = TextEditingController(
        text: _initialFor(field.payloadKey),
      );
    }
    if (_curated.isEmpty) _fullMode = true;
  }

  /// Curated + extras (when in full mode), preserving the curated order at
  /// the top so the most-frequent fields stay where users expect them after
  /// toggling.
  List<ProposalKindEditField> _currentFields() {
    if (!_fullMode) return _curated;
    final covered = <String>{for (final field in _curated) field.payloadKey};
    final extras = <ProposalKindEditField>[];
    for (final key in widget.plan.payload.keys) {
      if (covered.contains(key)) continue;
      if (_internalKeys.contains(key) || key.startsWith('_')) continue;
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: _initialFor(key)),
      );
      extras.add(ProposalKindEditField(payloadKey: key, label: _humanize(key)));
    }
    return [..._curated, ...extras];
  }

  bool get _hasExtraFields {
    final covered = <String>{for (final field in _curated) field.payloadKey};
    for (final key in widget.plan.payload.keys) {
      if (covered.contains(key)) continue;
      if (_internalKeys.contains(key) || key.startsWith('_')) continue;
      return true;
    }
    return false;
  }

  static String _humanize(String snakeCase) => snakeCase.replaceAll('_', ' ');

  String _initialFor(String key) {
    final overridden = widget.initial?[key];
    if (overridden != null) return overridden.toString();
    final raw = widget.plan.payload[key];
    return raw == null ? '' : raw.toString();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _collect() {
    final out = <String, Object?>{};
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      out[entry.key] = text;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(proposalKindRegistryProvider);
    _ensureInitialized(l10n);
    final fields = _currentFields();
    final showToggle = _curated.isNotEmpty && _hasExtraFields;
    return AppSheet(
      title: l10n.aiChatProposalEditKindTitle(
        proposalKindLabel(l10n, registry, widget.plan.kind),
      ),
      footer: AppSheetFooter(
        submitLabel: l10n.aiChatProposalSaveEdits,
        cancelLabel: l10n.commonCancel,
        onSubmit: () => Navigator.of(context).pop(_collect()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in fields) ...[
            FTextField(
              control: FTextFieldControl.managed(
                controller: _controllers[field.payloadKey],
              ),
              keyboardType: field.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              label: Text(field.label),
              hint: field.hint,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          if (showToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: FTappable(
                onPress: () => setState(() => _fullMode = !_fullMode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _fullMode
                            ? FLucideIcons.chevronUp
                            : FLucideIcons.chevronDown,
                        size: AppIconSizes.sm,
                        color: AiTone.active(context),
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      Text(
                        _fullMode
                            ? l10n.aiChatProposalEditStandardFields
                            : l10n.aiChatProposalEditMoreFields,
                        style: AiType.meta(
                          context,
                        ).copyWith(color: AiTone.active(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
