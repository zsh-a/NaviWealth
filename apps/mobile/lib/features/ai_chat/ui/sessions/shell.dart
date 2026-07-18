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
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s16,
                    AppSpacing.s8,
                    AppSpacing.s12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FLucideIcons.history,
                        size: AppIconSizes.h18,
                        color: colors.mutedForeground,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Text(
                        l10n.aiChatSessionsHeader,
                        style: context.rowTitleStyle.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                      const Spacer(),
                      if (onNew != null)
                        FTooltip(
                          tipBuilder: (_, _) =>
                              Text(l10n.aiChatNewSessionTooltip),
                          child: FButton.icon(
                            variant: FButtonVariant.secondary,
                            onPress: onNew,
                            child: const Icon(
                              FLucideIcons.plus,
                              size: AppIconSizes.h18,
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
                      AppSpacing.s10,
                    ),
                    child: searchBar!,
                  ),
              ],
            ),
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
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colors.border.withValues(alpha: AppOpacity.scrim),
          width: AppStroke.hairline,
        ),
      ),
      child: FTextField(
        control: FTextFieldControl.managed(
          controller: controller,
          // FTextFieldControl.managed passes a TextEditingValue, but for
          // search we only care about the string - unwrap here so callers
          // keep the cleaner ValueChanged<String> shape.
          onChange: (v) => onChanged(v.text),
        ),
        hint: l10n.aiChatSessionsSearchHint,
        maxLines: 1,
        keyboardType: TextInputType.text,
      ),
    );
  }
}
