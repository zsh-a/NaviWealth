import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../logging/providers.dart';
import 'form_undo.dart';

/// Shared business-operation feedback above the shell navigation.
class FormUndoBanner extends ConsumerStatefulWidget {
  const FormUndoBanner({super.key});

  @override
  ConsumerState<FormUndoBanner> createState() => _FormUndoBannerState();
}

class _FormUndoBannerState extends ConsumerState<FormUndoBanner> {
  FormUndoOffer? _running;
  FormUndoOffer? _failed;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(formUndoOfferProvider);
    if (offer == null) return const SizedBox.shrink();
    final busy = identical(_running, offer);
    final error = identical(_failed, offer) ? _error : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Semantics(
        liveRegion: true,
        child: AppStatusBanner(
          compact: true,
          kind: error == null ? AppStatusKind.success : AppStatusKind.error,
          message: error ?? offer.message,
          details: error == null ? null : offer.message,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBusyButton(
                label: error == null ? offer.actionLabel : offer.retryLabel,
                mainAxisSize: MainAxisSize.min,
                busy: busy,
                onPress: () => _undo(offer),
              ),
              AppIconButton(
                icon: FLucideIcons.x,
                tooltip: AppLocalizations.of(context).commonClose,
                onPress: busy
                    ? null
                    : () => ref
                          .read(formUndoOfferProvider.notifier)
                          .dismiss(offer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _undo(FormUndoOffer offer) async {
    if (_running != null) return;
    setState(() => _running = offer);
    try {
      final error = await ref
          .read(formUndoOfferProvider.notifier)
          .run(context, offer, ref.read(loggerProvider));
      if (mounted) {
        setState(() {
          _failed = error == null ? null : offer;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }
}
