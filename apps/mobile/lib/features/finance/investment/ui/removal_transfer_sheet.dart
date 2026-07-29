import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class RemovalTransferOption {
  const RemovalTransferOption({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}

Future<String?> showRemovalTransferSheet({
  required BuildContext context,
  required String title,
  required String description,
  required List<RemovalTransferOption> options,
}) {
  assert(options.isNotEmpty);
  return showAppSheet<String>(
    context: context,
    title: title,
    subtitle: description,
    builder: (_) => _RemovalTransferForm(options: options),
  );
}

class _RemovalTransferForm extends StatefulWidget {
  const _RemovalTransferForm({required this.options});

  final List<RemovalTransferOption> options;

  @override
  State<_RemovalTransferForm> createState() => _RemovalTransferFormState();
}

class _RemovalTransferFormState extends State<_RemovalTransferForm> {
  late String _selectedId = widget.options.first.id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.theme.colors.primary.withValues(
              alpha: AppOpacity.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              children: [
                Icon(
                  FLucideIcons.arrowRightLeft,
                  color: context.theme.colors.primary,
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Text(
                    l10n.portfolioRemovalTransferHint,
                    style: context.theme.typography.body.sm,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        FSelect<String>.rich(
          format: (id) =>
              widget.options.firstWhere((option) => option.id == id).title,
          control: FSelectControl<String>.lifted(
            value: _selectedId,
            onChange: (value) {
              if (value != null) setState(() => _selectedId = value);
            },
          ),
          label: Text(l10n.portfolioRemovalTransferTargetLabel),
          children: [
            for (final option in widget.options)
              FSelectItem<String>(
                value: option.id,
                title: Text(option.title),
                subtitle: option.subtitle == null
                    ? null
                    : Text(option.subtitle!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.portfolioRemovalTransferAction,
          destructive: true,
          onSubmit: () => Navigator.of(context).pop(_selectedId),
        ),
      ],
    );
  }
}
