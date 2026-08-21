import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/current_user.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/attachments/knowledge_attachment_store.dart';

/// "Insert image" affordance for KnowledgeOS markdown editors.
///
/// Presents camera / photo-library / file sources through the adaptive
/// action menu (popover on pointer platforms, bottom sheet on touch),
/// imports the pick through [KnowledgeAttachmentStore], and inserts the
/// `![name](attachment://<id>)` reference into [controller] at the cursor.
///
/// Renders nothing where attachment storage is unsupported (web phase A).
class KnowledgeImageInsertButton extends ConsumerWidget {
  const KnowledgeImageInsertButton({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(knowledgeAttachmentStoreProvider).asData?.value;
    if (store == null || !store.canWrite) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final platform = defaultTargetPlatform;
    final handheld =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;

    Future<void> importAndInsert(String fileName, Uint8List bytes) async {
      final attachment = await importKnowledgeImageBytes(
        ref,
        fileName: fileName,
        bytes: bytes,
      );
      if (!context.mounted) return;
      if (attachment == null) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeImageImportFailed,
        );
        return;
      }
      insertKnowledgeAttachmentMarkdown(controller, attachment);
    }

    Future<void> pick(ImageSource source) async {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 2048,
      );
      if (picked == null) return;
      await importAndInsert(picked.name, await picked.readAsBytes());
    }

    Future<void> pickFile() async {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final chunks = await file.readAsByteStream().toList();
      final bytes = Uint8List.fromList([for (final chunk in chunks) ...chunk]);
      await importAndInsert(file.name, bytes);
    }

    return AppAdaptiveActionMenu(
      title: l10n.knowledgeMarkdownInsertImage,
      actions: [
        if (handheld)
          AppAdaptiveAction(
            icon: FLucideIcons.camera,
            title: l10n.knowledgeImageSourceCamera,
            onPress: () => pick(ImageSource.camera),
          ),
        AppAdaptiveAction(
          icon: FLucideIcons.images,
          title: l10n.knowledgeImageSourceGallery,
          onPress: () => pick(ImageSource.gallery),
        ),
        AppAdaptiveAction(
          icon: FLucideIcons.folderOpen,
          title: l10n.knowledgeImageSourceFile,
          onPress: pickFile,
        ),
      ],
      triggerBuilder: (context, openMenu, focusNode) => FTooltip(
        tipBuilder: (_, _) => Text(l10n.knowledgeMarkdownInsertImage),
        child: Semantics(
          button: true,
          label: l10n.knowledgeMarkdownInsertImage,
          child: AppTappable(
            focusNode: focusNode,
            onPress: openMenu,
            child: SizedBox.square(
              dimension: AppControlHeights.touchTarget,
              child: Icon(
                FLucideIcons.image,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Imports one picked image through the attachment store.
///
/// Returns null when storage is unsupported or the import violates the
/// image policy (oversize / disallowed extension) — callers surface the
/// failure toast.
Future<KnowledgeAttachment?> importKnowledgeImageBytes(
  WidgetRef ref, {
  required String fileName,
  required Uint8List bytes,
}) async {
  final store = await ref.read(knowledgeAttachmentStoreProvider.future);
  if (!store.canWrite) return null;
  final ownerUserId = await ref.read(currentUserIdProvider)();
  try {
    return await store.importImage(
      ownerUserId: ownerUserId,
      fileName: fileName,
      bytes: bytes,
    );
  } on KnowledgeAttachmentImportRejected {
    return null;
  }
}

/// Inserts `![name](attachment://<id>)` at the cursor with blank-line
/// separation so the image parses as its own block paragraph.
void insertKnowledgeAttachmentMarkdown(
  TextEditingController controller,
  KnowledgeAttachment attachment,
) {
  final value = controller.value;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final snippet = '![${attachment.fileName}](${attachment.markdownSrc})';
  final before = value.text.substring(0, selection.start);
  final leading = before.isEmpty
      ? ''
      : before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final insertion = '$leading$snippet\n';
  final text = value.text.replaceRange(
    selection.start,
    selection.end,
    insertion,
  );
  controller.value = value.copyWith(
    text: text,
    selection: TextSelection.collapsed(
      offset: selection.start + insertion.length,
    ),
    composing: TextRange.empty,
  );
}
