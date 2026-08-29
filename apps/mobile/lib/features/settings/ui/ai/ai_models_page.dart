/// AI Models settings (D-1.7c).
///
/// Lets users download, verify, and delete optional device-model bundles for
/// memory retrieval and speech recognition. Native runtimes remain build-time
/// dependencies while model weights are explicit, user-controlled downloads.
///
/// Deliberately minimal UI:
///   - One card per bundle, status-driven (NotInstalled / Installing /
///     Installed / Failed)
///   - Download / Cancel / Delete buttons gated by status
///   - Per-file progress when downloading; aggregate when not
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/ai/local/embedding/embedder_diagnostics.dart';
import '../../../../core/ai/local/embedding/embedder_path_resolution.dart';
import '../../../../core/ai/local/embedding/model_install_state.dart';
import '../../../../core/ai/local/embedding/model_manifest.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/shell/settings_ui/inline_setting_row.dart';
import '../../../../core/shell/settings_ui/settings_page_frame.dart';
import '../../../../core/speech/speech_recognizer_provider.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

part 'models/bundle.dart';
part 'models/runtime.dart';
part 'models/shared.dart';

class AiModelsPage extends ConsumerWidget {
  const AiModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundles = ref.watch(knownModelBundlesProvider);
    final resolution = ref.watch(embedderPathResolutionProvider);
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.settingsAiModelsTitle,
      childPad: false,
      child: SettingsPageFrame(
        children: [
          if (kDebugMode) ...[
            _RuntimeDiagnosticsCard(resolution: resolution),
            const SizedBox(height: AppSpacing.s12),
          ],
          const _ActiveEmbedderCard(),
          const SizedBox(height: AppSpacing.s12),
          _SpeechRecognizerCard(bundles: bundles),
          const SizedBox(height: AppSpacing.s12),
          const _Hint(),
          const SizedBox(height: AppSpacing.s16),
          for (final bundle in bundles) ...[
            _BundleCard(bundle: bundle),
            const SizedBox(height: AppSpacing.s12),
          ],
          const SizedBox(height: AppSpacing.s16),
          const _Footnote(),
        ],
      ),
    );
  }
}
