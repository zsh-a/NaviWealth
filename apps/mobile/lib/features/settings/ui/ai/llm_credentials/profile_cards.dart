part of '../ai_llm_credentials_page.dart';

mixin _AiLlmCredentialsProfileCardsMixin on _AiLlmCredentialsPageStateBase {
  Widget _profileCard(
    BuildContext context,
    LlmProfile p, {
    required bool isActive,
  }) {
    final l10n = AppLocalizations.of(context);
    final meta = <String>[
      p.provider.label,
      _hostOf(p),
      if (p.model != null && p.model!.isNotEmpty) p.model!,
    ].join(' \u00b7 ');
    return AppChoiceTile(
      selected: isActive,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      onPress: isActive || _saving ? null : () => _activate(p.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.displayName,
                        style: context.labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    if (isActive)
                      AppBadge(
                        label: l10n.aiLlmActiveTag,
                        tone: AppBadgeTone.accent,
                        size: AppBadgeSize.compact,
                      )
                    else
                      Text(l10n.aiLlmTapToSwitch, style: context.captionStyle),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  meta,
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          _iconAction(
            context,
            FLucideIcons.pencil,
            l10n.aiLlmEditProvider,
            () => _openEditor(profile: p),
          ),
          _iconAction(
            context,
            FLucideIcons.trash2,
            l10n.commonDelete,
            () => _delete(p),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Text(l10n.aiLlmIntro, style: context.bodyCaptionStyle),
    );
  }

  Widget _unsupportedCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s14,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.aiLlmUnsupportedTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s6),
          Text(l10n.aiLlmUnsupportedBody, style: context.captionStyle),
        ],
      ),
    );
  }

  Widget _statusLine(
    BuildContext context,
    AsyncValue<LlmCredentials?> async,
    AppLocalizations l10n,
  ) {
    final text = switch (async) {
      AsyncData(:final value) when value?.isUsable == true =>
        '\u25cf ${l10n.aiLlmStatusActive(value!.active!.displayName)}',
      AsyncData(:final value) when (value?.profiles.isNotEmpty ?? false) =>
        '\u25cb ${l10n.aiLlmStatusSavedNoActive}',
      AsyncError() => l10n.aiLlmStatusReadFailed,
      _ => l10n.aiLlmStatusNotConfigured,
    };
    return Text(text, style: context.captionStyle);
  }

  @override
  Widget _label(BuildContext context, String text) => Text(
    text,
    style: context.captionLabelStyle.copyWith(
      color: context.theme.colors.mutedForeground,
    ),
  );

  Widget _iconAction(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPress,
  ) => AppIconButton(
    icon: icon,
    tooltip: tooltip,
    onPress: _saving ? null : onPress,
  );

  String _hostOf(LlmProfile profile) {
    final url = profile.baseUrl;
    if (url == null || url.trim().isEmpty) {
      return switch (profile.provider) {
        LlmProvider.anthropic => 'api.anthropic.com',
        LlmProvider.openai => 'api.openai.com',
      };
    }
    final u = Uri.tryParse(url.trim());
    if (u != null && u.host.isNotEmpty) return u.host;
    return url.trim();
  }
}
