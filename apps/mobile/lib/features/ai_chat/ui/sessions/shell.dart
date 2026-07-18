part of 'sessions_panel.dart';

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.onNew, required this.child, this.searchBar});

  final VoidCallback? onNew;
  final Widget child;

  /// Optional inline search box rendered between the header and the
  /// list. `null` collapses the section entirely so panels that never
  /// have anything to filter (login-required, error states) don't show
  /// a useless input.
  final Widget? searchBar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return ColoredBox(
      color: colors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s14,
              AppSpacing.s8,
              AppSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.aiChatSessionsHeader,
                    style: context.rowTitleStyle.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onNew != null)
                  FTooltip(
                    tipBuilder: (_, _) => Text(l10n.aiChatNewSessionTooltip),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: onNew,
                      child: Icon(
                        FLucideIcons.plus,
                        size: AppIconSizes.h18,
                        color: colors.foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (searchBar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                0,
                AppSpacing.s12,
                AppSpacing.s8,
              ),
              child: searchBar!,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.prominent),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: FTextField(
        control: FTextFieldControl.managed(
          controller: controller,
          onChange: (v) => onChanged(v.text),
        ),
        hint: l10n.aiChatSessionsSearchHint,
        maxLines: 1,
        keyboardType: TextInputType.text,
      ),
    );
  }
}
