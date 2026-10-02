import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../tokens/dimens_tokens.dart';
import 'app_actions.dart';
import 'app_status_banner.dart';

class AppDraftRestoreBanner extends StatelessWidget {
  const AppDraftRestoreBanner({
    super.key,
    required this.onRestore,
    required this.onDiscard,
  });
  final VoidCallback onRestore;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStatusBanner(message: l10n.formDraftAvailable),
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            AppActionButton(
              mainAxisSize: MainAxisSize.min,
              onPress: onRestore,
              child: Flexible(child: Text(l10n.formDraftRestore)),
            ),
            AppActionButton(
              mainAxisSize: MainAxisSize.min,
              variant: FButtonVariant.outline,
              onPress: onDiscard,
              child: Flexible(child: Text(l10n.formDraftDiscard)),
            ),
          ],
        ),
      ],
    );
  }
}
