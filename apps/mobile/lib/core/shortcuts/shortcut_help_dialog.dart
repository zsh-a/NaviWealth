import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/gen/app_localizations.dart';
import 'shortcut_bindings.dart';

/// Shows the keyboard shortcut help dialog. Idempotent: a second invocation
/// while the dialog is already open is a no-op.
Future<void> showShortcutHelpDialog(BuildContext context) {
  if (_isOpen) return Future<void>.value();
  _isOpen = true;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) => const _ShortcutHelpDialog(),
  ).whenComplete(() => _isOpen = false);
}

bool _isOpen = false;

class _ShortcutHelpDialog extends StatelessWidget {
  const _ShortcutHelpDialog();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    // Deduplicate by descriptionKey so the meta/control variants of the same
    // intent show as a single row.
    final Map<String, ShortcutBinding> dedup = <String, ShortcutBinding>{};
    for (final ShortcutBinding b in globalShortcutBindings()) {
      dedup.putIfAbsent(b.descriptionKey, () => b);
    }

    return AlertDialog(
      title: Text(l10n.shortcutsHelpTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ShortcutBinding b in dedup.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_descriptionFor(l10n, b.descriptionKey)),
                    ),
                    _ActivatorBadge(activator: b.activator),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
      // Keep title color predictable across themes.
      titleTextStyle: theme.textTheme.titleLarge,
    );
  }

  String _descriptionFor(AppLocalizations l10n, String key) {
    switch (key) {
      case 'shortcutCommandPalette':
        return l10n.shortcutCommandPalette;
      case 'shortcutShowHelp':
        return l10n.shortcutShowHelp;
      case 'shortcutDismissOverlay':
        return l10n.shortcutDismissOverlay;
      case 'shortcutToggleSidebar':
        return l10n.shortcutToggleSidebar;
      case 'shortcutSwitchTab0':
        return l10n.shortcutSwitchTab(1, l10n.navHome);
      case 'shortcutSwitchTab1':
        return l10n.shortcutSwitchTab(2, l10n.navAssets);
      case 'shortcutSwitchTab2':
        return l10n.shortcutSwitchTab(3, l10n.navExpenses);
      case 'shortcutSwitchTab3':
        return l10n.shortcutSwitchTab(4, l10n.navAnalytics);
      case 'shortcutSwitchTab4':
        return l10n.shortcutSwitchTab(5, l10n.navFire);
      case 'shortcutSwitchTab5':
        return l10n.shortcutSwitchTab(6, l10n.navSettings);
    }
    return key;
  }
}

class _ActivatorBadge extends StatelessWidget {
  const _ActivatorBadge({required this.activator});

  final ShortcutActivator activator;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> labels = _labelsFor(activator);
    return Wrap(
      spacing: 4,
      children: <Widget>[
        for (final String label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  List<String> _labelsFor(ShortcutActivator activator) {
    if (activator is! SingleActivator) {
      return <String>[activator.toString()];
    }
    final List<String> parts = <String>[];
    if (activator.meta) parts.add('⌘');
    if (activator.control) parts.add('Ctrl');
    if (activator.alt) parts.add('Alt');
    if (activator.shift) parts.add('Shift');
    parts.add(_keyLabel(activator.trigger));
    return parts;
  }

  String _keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.slash) return '/';
    final String label = key.keyLabel;
    return label.isEmpty ? key.debugName ?? '?' : label;
  }
}
