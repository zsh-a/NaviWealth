import 'package:flutter/material.dart' show Colors, Navigator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'command_palette_entry.dart';
import 'local_query_result_pane_provider.dart';

/// Show the global command palette. Idempotent — a second call while the
/// palette is already on screen is a no-op so the Cmd+K binding stays safe to
/// hammer.
///
/// [onAskAi] is called with the user's query when a domain-provided local
/// result pane offers a "continue in AI history" affordance. Core owns the
/// palette chrome; domains can contribute the inline result pane through
/// [localQueryResultPaneBuilderProvider].
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteEntry> commands,
  void Function(String query)? onAskAi,
}) {
  final current = _openDialog;
  final navigator = Navigator.of(context);
  if (current != null && _openNavigator == navigator && navigator.mounted) {
    return current;
  }
  final future = showFDialog<void>(
    context: context,
    barrierDismissible: true,
    routeSettings: const RouteSettings(name: _kCommandPaletteRouteName),
    // NB: we intentionally do *not* wrap in `FDialog.raw`. forui's dialog
    // vertically centres its (min-sized) child and reserves the keyboard as
    // bottom padding, so on mobile the palette floats to the middle and leaves
    // a keyboard-sized blank band once the list shrinks while typing. The
    // palette presents its own top-anchored, keyboard-aware surface instead.
    builder: (_, _, animation) => _CommandPaletteDialog(
      commands: commands,
      onAskAi: onAskAi,
      animation: animation,
    ),
  );
  _openNavigator = navigator;
  late final Future<void> guarded;
  guarded = future.whenComplete(() {
    if (identical(_openDialog, guarded)) {
      _openDialog = null;
      _openNavigator = null;
    }
  });
  _openDialog = guarded;
  return guarded;
}

@visibleForTesting
bool get debugCommandPaletteOpen => _openDialog != null;

/// Test-only: clear the open-guard so a previous test that bailed before the
/// dialog popped doesn't make the next call a no-op.
@visibleForTesting
void resetCommandPaletteForTest() {
  _openDialog = null;
  _openNavigator = null;
}

const String _kCommandPaletteRouteName = 'command-palette';
Future<void>? _openDialog;
NavigatorState? _openNavigator;
const double _kCommandRowExtent = AppSpacing.s56;

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog({
    required this.commands,
    required this.animation,
    this.onAskAi,
  });

  final List<CommandPaletteEntry> commands;
  final void Function(String query)? onAskAi;

  /// The route's entrance animation, used to fade the palette in (forui's
  /// `FDialog` normally owns this; we drive it ourselves so we can control the
  /// palette's position).
  final Animation<double> animation;

  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<_CommandPaletteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();

  late List<CommandPaletteEntry> _filtered = widget.commands;
  int _selectedIndex = 0;
  String _query = '';

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

    setState(() {
      _query = raw;
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
    const double itemExtent = _kCommandRowExtent;
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

  void _onContinueInChat(String query) {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    if (widget.onAskAi != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAskAi!(query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MediaQueryData media = MediaQuery.of(context);
    final Size mediaSize = media.size;
    final double keyboardInset = media.viewInsets.bottom;

    final double maxWidth = mediaSize.width < 560 ? mediaSize.width - 48 : 520;
    final double maxHeight = mediaSize.height * 0.6;

    final localQueryResultPaneBuilder = ref.watch(
      localQueryResultPaneBuilderProvider,
    );

    final Widget card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.border, width: AppStroke.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Focus(
                onKeyEvent: _onKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s12,
                    AppSpacing.s12,
                    AppSpacing.s12,
                    AppSpacing.s8,
                  ),
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
                      child: Icon(FLucideIcons.search, size: AppIconSizes.h18),
                    ),
                  ),
                ),
              ),
              const FDivider(),
              if (_query.isNotEmpty && localQueryResultPaneBuilder != null)
                localQueryResultPaneBuilder(
                  query: _query,
                  now: DateTime.now(),
                  onContinueInChat: widget.onAskAi == null
                      ? null
                      : _onContinueInChat,
                ),
              Flexible(
                child: _filtered.isEmpty
                    ? _EmptyState(message: l10n.commandPaletteEmpty)
                    : ListView.builder(
                        controller: _listScroll,
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemExtent: _kCommandRowExtent,
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
      ),
    );

    // Top-anchor the palette and reserve the keyboard's height ourselves so the
    // search field stays pinned near the top and the result list grows downward
    // toward the keyboard. The space below the (min-sized) card is the dimmed
    // barrier, never an opaque blank band — and the field no longer jumps as the
    // list filters while typing.
    return FadeTransition(
      opacity: widget.animation,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s12,
            AppSpacing.s16,
            keyboardInset + 12,
          ),
          child: Align(alignment: Alignment.topCenter, child: card),
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
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final Color background = selected ? colors.muted : Colors.transparent;
    final Color labelColor = colors.foreground;
    final Color iconColor = colors.mutedForeground;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      cursor: SystemMouseCursors.click,
      child: FTappable(
        onPress: onTap,
        child: Container(
          color: background,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: AppIconSizes.md, color: iconColor),
              const SizedBox(width: AppSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      entry.label,
                      style:
                          (selected
                                  ? context.labelStyle
                                  : typography.body.sm.copyWith(
                                      fontWeight: FontWeight.w400,
                                    ))
                              .copyWith(color: labelColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.subtitle != null)
                      Text(
                        entry.subtitle!,
                        style: context.captionStyle.copyWith(color: iconColor),
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
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s32,
        horizontal: AppSpacing.s16,
      ),
      child: Center(child: Text(message, style: context.bodyCaptionStyle)),
    );
  }
}
