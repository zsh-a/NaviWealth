import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';

part 'sessions_panel_groups.dart';
part 'sessions_panel_shell.dart';
part 'sessions_panel_states.dart';
part 'sessions_panel_tiles.dart';

/// List of past chat sessions. Used as a permanent sidebar on
/// tablet/desktop, and as a right-slide [showFSheet] panel on mobile.
///
/// Renders an empty-state cell when the user has never chatted, plus a
/// "+" affordance the surrounding page handles by opening a brand-new
/// session. Sessions are grouped by recency (Today / Yesterday / This
/// week / This month / Older) and filterable through an inline search
/// box that appears once there's something to filter.
class SessionsPanel extends ConsumerStatefulWidget {
  const SessionsPanel({
    super.key,
    required this.activeSessionId,
    required this.onSelect,
    required this.onNew,
  });

  final String? activeSessionId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  @override
  ConsumerState<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends ConsumerState<SessionsPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Device-only AI is account-less; scope sessions by the active user id
    // ([kLocalOnlyUserId] in local-only mode). `null` only before auth settles.
    final userId = ref.watch(activeUserIdProvider);

    if (userId == null) {
      return _PanelShell(
        onNew: null,
        child: _PanelMessage(
          icon: FLucideIcons.lock,
          message: l10n.aiChatLoginRequired,
        ),
      );
    }

    final sessionsAsync = ref.watch(chatSessionsStreamProvider(userId));
    return _PanelShell(
      onNew: widget.onNew,
      // Surface the search box once there's at least one session — for
      // a single thread the affordance is just noise.
      searchBar: sessionsAsync.maybeWhen(
        data: (s) => s.isEmpty
            ? null
            : _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
              ),
        orElse: () => null,
      ),
      child: sessionsAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: AppSpacing.s24,
            height: AppSpacing.s24,
            child: FCircularProgress(),
          ),
        ),
        error: (e, _) => _PanelMessage(
          icon: FLucideIcons.circleAlert,
          iconColor: context.theme.colors.destructive,
          message: l10n.commonLoadError(e.toString()),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _PanelMessage(
              icon: FLucideIcons.messageCircle,
              message: l10n.aiChatSessionsEmpty,
              action: FButton(
                variant: FButtonVariant.primary,
                onPress: widget.onNew,
                prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
                child: Text(l10n.aiChatNewSessionTooltip),
              ),
            );
          }
          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? sessions
              : sessions
                    .where((s) => s.title.toLowerCase().contains(query))
                    .toList(growable: false);
          if (filtered.isEmpty) {
            return _PanelMessage(
              icon: FLucideIcons.searchX,
              message: l10n.aiChatSessionsSearchEmpty(_query),
            );
          }
          final now = DateTime.now();
          final groups = _groupByRecency(filtered, now, l10n);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s8,
            ),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (i > 0) const SizedBox(height: AppSpacing.s10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s8,
                      AppSpacing.s4,
                      AppSpacing.s8,
                      AppSpacing.s4,
                    ),
                    child: Text(
                      group.label,
                      style: context.microLabelStyle.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                  for (final s in group.sessions) ...[
                    _SessionTile(
                      session: s,
                      selected: s.id == widget.activeSessionId,
                      onTap: () => widget.onSelect(s.id),
                      onDelete: () => _confirmDelete(context, ref, s),
                      onRename: () => _promptRename(context, ref, s),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ChatSession session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showAppFormSheet<bool>(
      context: context,
      builder: (ctx) => AppSheet(
        title: l10n.aiChatSessionDeleteTitle,
        footer: AppSheetFooter(
          submitLabel: l10n.commonDelete,
          cancelLabel: l10n.commonCancel,
          destructive: true,
          onSubmit: () => Navigator.of(ctx).pop(true),
        ),
        child: Text(
          l10n.aiChatSessionDeleteBody(session.title),
          style: context.bodyCaptionStyle.copyWith(height: 1.4),
        ),
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.deleteSession(session.id);
  }

  Future<void> _promptRename(
    BuildContext context,
    WidgetRef ref,
    ChatSession session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: session.title);
    final result = await showGuardedFormSheet<String>(
      context: context,
      builder: (ctx, dirty) {
        // Idempotent — bindTextControllers no-ops after the first call.
        dirty.bindTextControllers([controller]);
        return AppSheet(
          title: l10n.aiChatSessionRenameTitle,
          footer: AppSheetFooter(
            submitLabel: l10n.commonSave,
            cancelLabel: l10n.commonCancel,
            onSubmit: () {
              dirty.markPristine();
              Navigator.of(ctx).pop(controller.text.trim());
            },
          ),
          child: FTextField(
            control: FTextFieldControl.managed(controller: controller),
            autofocus: true,
            maxLength: 60,
            label: Text(l10n.aiChatSessionTitleLabel),
          ),
        );
      },
    );
    if (result == null || result.isEmpty || result == session.title) return;
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.renameSession(session.id, result);
  }
}
