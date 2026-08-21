import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/attachments/knowledge_attachment_store.dart';

/// Renders an `attachment://` image referenced from KnowledgeOS markdown.
///
/// Loads bytes through [knowledgeAttachmentStoreProvider]: a loading skeleton
/// while in flight, the shared image placeholder chip when the bytes are
/// unavailable (web, or a note synced from another device in phase A where
/// attachments are device-local), and the decoded image once resolved.
class KnowledgeAttachmentImage extends ConsumerWidget {
  const KnowledgeAttachmentImage({
    super.key,
    required this.attachmentId,
    required this.alt,
    this.block = false,
  });

  final String attachmentId;
  final String alt;

  /// Standalone-paragraph rendering: wider bounds and vertical breathing
  /// room. Inline (mixed into a text run) stays compact.
  final bool block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = AppLocalizations.of(context).knowledgeMarkdownImageLabel(alt);
    final bytes = ref.watch(_attachmentBytesProvider(attachmentId));

    return Semantics(
      image: true,
      label: label,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: block ? AppSpacing.s4 : AppSpacing.s0,
        ),
        child: switch (bytes) {
          AsyncData(:final value) when value != null => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: block ? 360 : 180,
                maxWidth: block ? double.infinity : 320,
              ),
              child: Image.memory(value, fit: BoxFit.contain),
            ),
          ),
          AsyncData() => _UnavailableImage(label: label),
          _ => SkeletonBox(height: block ? 160 : 96, radius: AppRadius.lg),
        },
      ),
    );
  }
}

class _UnavailableImage extends StatelessWidget {
  const _UnavailableImage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.prominent),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FLucideIcons.imageOff,
            size: AppIconSizes.xs,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s4),
          Flexible(
            child: Text(
              label,
              style: TypographyTokens.bodySmall.copyWith(
                color: colors.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

final _attachmentBytesProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  id,
) async {
  final store = await ref.watch(knowledgeAttachmentStoreProvider.future);
  return store.readBytes(id);
});
