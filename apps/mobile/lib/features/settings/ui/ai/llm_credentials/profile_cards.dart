part of '../ai_llm_credentials_page.dart';

mixin _AiLlmCredentialsProfileCardsMixin on _AiLlmCredentialsPageStateBase {
  Widget _profileCard(
    BuildContext context,
    LlmProfile p, {
    required bool isActive,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final meta = <String>[
      p.provider.label,
      _hostOf(p),
      if (p.model != null && p.model!.isNotEmpty) p.model!,
    ].join(' \u00b7 ');
    final card = SoftCard.flat(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      onPress: isActive ? null : () => _activate(p.id),
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
                      _tag(context, l10n.aiLlmActiveTag, colors.primary)
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
            () => _openEditor(profile: p),
          ),
          _iconAction(context, FLucideIcons.trash2, () => _delete(p)),
        ],
      ),
    );
    if (!isActive) return card;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colors.primary.withValues(alpha: AppOpacity.disabled),
          width: 1.5,
        ),
      ),
      child: card,
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

  Widget _tag(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s8,
      vertical: AppSpacing.s2,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: AppOpacity.medium),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(text, style: context.captionLabelStyle.copyWith(color: color)),
  );

  Widget _iconAction(
    BuildContext context,
    IconData icon,
    VoidCallback onPress,
  ) => FTappable(
    onPress: onPress,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Icon(
        icon,
        size: AppIconSizes.h18,
        color: context.theme.colors.mutedForeground,
      ),
    ),
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
