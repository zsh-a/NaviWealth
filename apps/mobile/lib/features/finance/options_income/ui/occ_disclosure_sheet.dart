import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';

const String _kOccOddUrl =
    'https://www.theocc.com/company-information/documents-and-archives/options-disclosure-document';

/// First-run OCC ODD disclosure (`docs/domains/options-income.md` §11.2).
///
/// On accept the user's [OptionsStrategyProfile] is upserted with
/// `riskDisclosureAckAt = now`. The page gates the scanner UI behind a
/// non-null ack timestamp, so callers can resume the regular flow on
/// pop.
Future<bool> showOccDisclosureSheet(BuildContext context) async {
  final result = await showAppFormSheet<bool>(
    context: context,
    builder: (_) => const _OccDisclosureSheet(),
  );
  return result ?? false;
}

class _OccDisclosureSheet extends ConsumerStatefulWidget {
  const _OccDisclosureSheet();

  @override
  ConsumerState<_OccDisclosureSheet> createState() =>
      _OccDisclosureSheetState();
}

class _OccDisclosureSheetState extends ConsumerState<_OccDisclosureSheet> {
  bool _busy = false;
  bool _understood = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(
        optionsStrategyProfileRepositoryProvider.future,
      );
      final existing = await ref.read(optionsStrategyProfileProvider.future);
      // First-run: seed a Balanced profile with the disclosure timestamp
      // set. Subsequent acks (e.g. legal text revision) re-upsert with
      // the same body.
      final profile =
          (existing ?? defaultProfileForMode(OptionsStrategyMode.balanced))
              .copyWith(riskDisclosureAckAt: DateTime.now().toUtc());
      await repo.upsert(profile);
      ref.invalidate(optionsStrategyProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerProfileSaveError,
      );
    }
  }

  Future<void> _openOdd() async {
    final launched = await launchUrl(
      Uri.parse(_kOccOddUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).aiChatLinkOpenFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return AppSheet(
      title: l10n.incomePlannerOccTitle,
      subtitle: l10n.incomePlannerOccSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerOccAccept,
        cancelLabel: l10n.incomePlannerOccCancel,
        onSubmit: _accept,
        busy: _busy,
        enabled: _understood,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.incomePlannerOccBody,
            style: context.bodyCaptionStyle.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.s16),
          FButton(
            variant: FButtonVariant.outline,
            onPress: _openOdd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FLucideIcons.externalLink,
                  size: AppIconSizes.sm,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(l10n.incomePlannerOccLearnMore),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          AppTappable(
            onPress: () => setState(() => _understood = !_understood),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FCheckbox(
                    value: _understood,
                    onChange: (value) => setState(() => _understood = value),
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Text(
                      l10n.incomePlannerOccConfirmation,
                      style: context.bodyCaptionStyle.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
