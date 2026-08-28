import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'shortcut_bindings.dart';

/// Shows the keyboard shortcut help dialog. Idempotent: a second invocation
/// while the dialog is already open is a no-op.
Future<void> showShortcutHelpDialog(BuildContext context) {
  if (_isOpen) return Future<void>.value();
  _isOpen = true;
  return showAppSheet<void>(
    context: context,
    title: AppLocalizations.of(context).shortcutsHelpTitle,
    builder: (_) => const _ShortcutHelpSheet(),
  ).whenComplete(() => _isOpen = false);
}

bool _isOpen = false;

class _ShortcutHelpSheet extends StatelessWidget {
  const _ShortcutHelpSheet();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Deduplicate by descriptionKey so the meta/control variants of the same
    // intent show as a single row.
    final Map<String, ShortcutBinding> dedup = <String, ShortcutBinding>{};
    for (final ShortcutBinding b in globalShortcutBindings()) {
      dedup.putIfAbsent(b.descriptionKey, () => b);
    }

    // Add vim-style navigation entries that aren't in the bindings map.
    final List<_ManualShortcutEntry> manualEntries = <_ManualShortcutEntry>[
      _ManualShortcutEntry(
        label: l10n.shortcutVimGoto(l10n.navHome),
        keys: 'g h',
      ),
      _ManualShortcutEntry(
        label: l10n.shortcutVimGoto(l10n.navActivity),
        keys: 'g a',
      ),
      _ManualShortcutEntry(
        label: l10n.shortcutVimGoto(l10n.navAccounts),
        keys: 'g n',
      ),
      _ManualShortcutEntry(
        label: l10n.shortcutVimGoto(l10n.navSettings),
        keys: 'g s',
      ),
      // Master-detail list navigation (only active in list panes).
      _ManualShortcutEntry(label: l10n.shortcutListSearch, keys: '/'),
      _ManualShortcutEntry(label: l10n.shortcutListNext, keys: 'j'),
      _ManualShortcutEntry(label: l10n.shortcutListPrevious, keys: 'k'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final ShortcutBinding b in dedup.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Row(
              children: [
                Expanded(child: Text(_descriptionFor(l10n, b.descriptionKey))),
                _ActivatorBadge(activator: b.activator),
              ],
            ),
          ),
        for (final _ManualShortcutEntry e in manualEntries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Row(
              children: [
                Expanded(child: Text(e.label)),
                _KeyLabelBadge(label: e.keys),
              ],
            ),
          ),
      ],
    );
  }

  String _descriptionFor(AppLocalizations l10n, String key) {
    switch (key) {
      case 'shortcutCommandPalette':
        return l10n.shortcutCommandPalette;
      case 'shortcutShowHelp':
        return l10n.shortcutShowHelp;
      case 'shortcutOpenAiChat':
        return l10n.shortcutOpenAiChat;
      case 'shortcutDismissOverlay':
        return l10n.shortcutDismissOverlay;
      case 'shortcutToggleSidebar':
        return l10n.shortcutToggleSidebar;
      case 'shortcutSwitchTab0':
        return l10n.shortcutSwitchTab(1, l10n.navHome);
      case 'shortcutSwitchTab1':
        return l10n.shortcutSwitchTab(2, l10n.navActivity);
      case 'shortcutSwitchTab2':
        return l10n.shortcutSwitchTab(3, l10n.navWealth);
      case 'shortcutSwitchTab3':
        return l10n.shortcutSwitchTab(4, l10n.navPlan);
    }
    return key;
  }
}

class _ManualShortcutEntry {
  const _ManualShortcutEntry({required this.label, required this.keys});
  final String label;
  final String keys;
}

class _ActivatorBadge extends StatelessWidget {
  const _ActivatorBadge({required this.activator});

  final ShortcutActivator activator;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = _labelsFor(activator);
    return Wrap(
      spacing: AppSpacing.s4,
      children: <Widget>[
        for (final String label in labels)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: context.theme.colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.theme.colors.border),
            ),
            child: Text(
              label,
              style: context.theme.typography.body.xs2.copyWith(
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

/// Badge for key sequences (e.g. "g h") that aren't a single [ShortcutActivator].
class _KeyLabelBadge extends StatelessWidget {
  const _KeyLabelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: context.theme.colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.theme.colors.border),
      ),
      child: Text(
        label,
        style: context.theme.typography.body.xs2.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
