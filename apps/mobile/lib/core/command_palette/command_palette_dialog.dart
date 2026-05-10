import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'command_palette_entry.dart';

/// Show the global command palette. Idempotent — a second call while the
/// palette is already on screen is a no-op so the Cmd+K binding stays safe to
/// hammer.
///
/// [onAskAi] is called with the user's query when they select the dynamic
/// "Ask AI: …" entry that appears when the search text doesn't fully match
/// any command.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteEntry> commands,
  void Function(String query)? onAskAi,
}) {
  if (_isOpen) return Future<void>.value();
  _isOpen = true;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (BuildContext ctx) =>
        _CommandPaletteDialog(commands: commands, onAskAi: onAskAi),
  ).whenComplete(() => _isOpen = false);
}

@visibleForTesting
bool get debugCommandPaletteOpen => _isOpen;

/// Test-only: clear the open-guard so a previous test that bailed before the
/// dialog popped doesn't make the next call a no-op.
@visibleForTesting
void resetCommandPaletteForTest() {
  _isOpen = false;
}

bool _isOpen = false;

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.commands, this.onAskAi});

  final List<CommandPaletteEntry> commands;
  final void Function(String query)? onAskAi;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();

  late List<CommandPaletteEntry> _filtered = widget.commands;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final String raw = _searchController.text.trim();
    final String q = raw.toLowerCase();
    final List<CommandPaletteEntry> next = q.isEmpty
        ? widget.commands
        : widget.commands.where((c) => c.matches(q)).toList(growable: false);

    // Prepend a dynamic "Ask AI" entry when the user has typed a query.
    if (raw.isNotEmpty && widget.onAskAi != null) {
      final l10n = AppLocalizations.of(context);
      final aiEntry = CommandPaletteEntry(
        id: 'action.askAi',
        label: l10n.commandPaletteAskAi(raw),
        icon: Icons.auto_awesome,
        keywords: <String>[raw, 'ai', 'ask'],
        run: (_) => widget.onAskAi!(raw),
      );
      next.insert(0, aiEntry);
    }

    setState(() {
      _filtered = next;
      _selectedIndex = next.isEmpty
          ? 0
          : _selectedIndex.clamp(0, next.length - 1);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _invokeSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final int next = (_selectedIndex + delta) % _filtered.length;
    setState(() {
      _selectedIndex = next < 0 ? next + _filtered.length : next;
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    if (!_listScroll.hasClients) return;
    const double itemExtent = 56;
    final double target = _selectedIndex * itemExtent;
    final double viewportHeight = _listScroll.position.viewportDimension;
    final double offset = _listScroll.offset;
    if (target < offset) {
      _listScroll.jumpTo(target);
    } else if (target + itemExtent > offset + viewportHeight) {
      _listScroll.jumpTo(target + itemExtent - viewportHeight);
    }
  }

  void _invokeSelected() {
    if (_filtered.isEmpty) return;
    _invoke(_filtered[_selectedIndex]);
  }

  void _invoke(CommandPaletteEntry entry) {
    final NavigatorState navigator = Navigator.of(context);
    final BuildContext rootContext = navigator.context;
    navigator.pop();
    // Run after the dialog has been popped so go_router navigation doesn't
    // race against the dialog teardown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      entry.run(rootContext);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Size mediaSize = MediaQuery.sizeOf(context);

    final double maxWidth = mediaSize.width < 560 ? mediaSize.width - 48 : 520;
    final double maxHeight = mediaSize.height * 0.6;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Focus(
              onKeyEvent: _onKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _searchController,
                  ),
                  focusNode: _searchFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  hint: l10n.commandPaletteSearchHint,
                  prefixBuilder: (ctx, style, variants) => const Padding(
                    padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                    child: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _filtered.isEmpty
                  ? _EmptyState(
                      message: l10n.commandPaletteEmpty,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : ListView.builder(
                      controller: _listScroll,
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemExtent: 56,
                      itemBuilder: (BuildContext _, int i) {
                        final CommandPaletteEntry entry = _filtered[i];
                        final bool selected = i == _selectedIndex;
                        return _CommandRow(
                          entry: entry,
                          selected: selected,
                          onTap: () => _invoke(entry),
                          onHover: (bool hovering) {
                            if (hovering && !selected) {
                              setState(() => _selectedIndex = i);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CommandPaletteEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = selected
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.transparent;
    final Color labelColor = theme.colorScheme.onSurface;
    final Color iconColor = theme.colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: 20, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      entry.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: labelColor,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.subtitle != null)
                      Text(
                        entry.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: iconColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}
