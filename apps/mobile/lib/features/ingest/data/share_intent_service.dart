/// §5.10.10 / S5c-native — receive shares from other apps.
///
/// `receive_sharing_intent` surfaces files/text the user "Share"d into
/// NaviWealth (iOS Share Extension / Android SEND intent). Each share
/// is funnelled through the existing pipeline (privacy gate → device parser
/// or provider Vision) and the user is dropped on the review queue.
///
/// Hard-guarded: every plugin call is wrapped so the host test VM /
/// web / desktop (no plugin registered → `MissingPluginException`)
/// is a silent no-op. The app must never crash because a share
/// channel is absent.
library;

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:uuid/uuid.dart';

import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../knowledge/data/providers.dart' as know_data;
import '../../knowledge/domain/knowledge_models.dart';
import '../domain/ingest_models.dart';
import 'ingest_capture_source.dart';
import 'providers.dart';
import 'share_intent_navigation.dart';

const _kShareUuid = Uuid();

class ShareIntentService {
  ShareIntentService(this._ref);

  final Ref _ref;
  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _started = false;

  /// Idempotent. Safe to call from `AppDockShell.initState`.
  void start() {
    if (_started) return;
    _started = true;
    try {
      // Cold start: the app was launched by a share.
      unawaited(
        ReceiveSharingIntent.instance
            .getInitialMedia()
            .then((files) async {
              if (files.isEmpty) return;
              await _handle(files);
              try {
                await ReceiveSharingIntent.instance.reset();
              } catch (_) {}
            })
            .catchError((Object _) {}),
      );
      // Warm: shared while the app is already running.
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        _handle,
        onError: (Object _) {},
      );
    } catch (_) {
      // No share channel here (tests / web / desktop) — no-op.
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    // Two-rail dispatch (`docs/domains/knowledgeos-domain.md` §5 quick capture
    // pipeline). text/url shares hit the Knowledge Inbox when the
    // user opted into the Knowledge domain; image/file shares always
    // go to the Finance ingest pipeline (receipt OCR / parser path).
    // Finance keeps text shares only when Knowledge is OFF — text
    // receipts (forwarded bank SMS etc.) still need a home there.
    final knowledgeOn =
        _ref
            .read(core_auth.domainOptInsProvider)
            .value
            ?.contains(DomainScope.knowledge) ??
        false;

    var handledFinance = false;
    var handledKnowledge = false;
    for (final f in files) {
      try {
        if (knowledgeOn &&
            (f.type == SharedMediaType.text || f.type == SharedMediaType.url)) {
          await _captureKnowledgeNote(f);
          handledKnowledge = true;
          continue;
        }
        final source = await _toSource(f);
        if (source == null) continue;
        await _ref.read(ingestControllerProvider).ingest(source);
        handledFinance = true;
      } catch (_) {
        // One bad share never blocks the rest.
      }
    }
    if (handledFinance) {
      _navigate(ShareIntentDestination.financeIngest);
    } else if (handledKnowledge) {
      _navigate(ShareIntentDestination.knowledgeInbox);
    }
  }

  void _navigate(ShareIntentDestination destination) {
    try {
      _ref.read(shareIntentNavigationSinkProvider)(destination);
    } catch (_) {}
  }

  /// Direct-write a [KnowledgeNote] from a text / url share. Title is
  /// auto-derived from the first line; the rest goes into `body_md`.
  /// URLs land in `source_url` so the Inbox card can render the link
  /// while keeping the user's annotation in the body.
  Future<void> _captureKnowledgeNote(SharedMediaFile f) async {
    final raw = f.path.trim();
    if (raw.isEmpty) return;
    final repo = await _ref.read(know_data.knowledgeRepositoryProvider.future);
    final stamper = await _ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    final isUrl =
        f.type == SharedMediaType.url ||
        raw.startsWith('http://') ||
        raw.startsWith('https://');
    final firstLine = raw.split('\n').first.trim();
    final title = firstLine.length > 80
        ? '${firstLine.substring(0, 80)}…'
        : firstLine;
    await repo.upsertNote(
      KnowledgeNote(
        id: _kShareUuid.v4(),
        title: title.isEmpty ? '(shared)' : title,
        bodyMd: raw,
        sourceUrl: isUrl ? raw : null,
        tags: const <String>['source:share'],
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      ),
    );
  }

  Future<IngestSource?> _toSource(SharedMediaFile f) async {
    if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
      final text = f.path.trim();
      if (text.isEmpty) return null;
      return IngestSource(
        kind: IngestSourceKind.pasteText,
        payload: text,
        originLabel: 'share',
      );
    }
    if (f.type == SharedMediaType.image || f.type == SharedMediaType.file) {
      return xFileToIngestSource(XFile(f.path));
    }
    // video / anything else — not an ingest input.
    return null;
  }
}

final shareIntentServiceProvider = Provider<ShareIntentService>(
  ShareIntentService.new,
);
