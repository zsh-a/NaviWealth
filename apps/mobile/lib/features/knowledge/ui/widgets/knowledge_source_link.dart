import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/knowledge_source_url.dart';

typedef KnowledgeSourceLauncher = Future<bool> Function(Uri uri);

class KnowledgeSourceLink extends StatelessWidget {
  const KnowledgeSourceLink({
    super.key,
    required this.sourceUrl,
    this.launcher,
  });

  final String sourceUrl;
  final KnowledgeSourceLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final uri = parseKnowledgeSourceUrl(sourceUrl);
    if (uri == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: '${l10n.knowledgeSourceOpenAction}: ${knowledgeSourceHost(uri)}',
      child: SoftCard.flat(
        key: const Key('knowledge-source-link'),
        padding: const EdgeInsets.all(AppSpacing.s12),
        onPress: () => _open(context, uri),
        child: Row(
          children: [
            Icon(
              FLucideIcons.link2,
              size: AppIconSizes.sm,
              color: colors.primary,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    knowledgeSourceHost(uri),
                    style: context.theme.typography.body.sm.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    uri.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              FLucideIcons.externalLink,
              size: AppIconSizes.xs,
              color: colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final open = launcher ?? _launchExternally;
    var launched = false;
    try {
      launched = await open(uri);
    } on Object {
      launched = false;
    }
    if (!launched && context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).knowledgeSourceOpenFailed,
      );
    }
  }
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
