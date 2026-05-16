/// §5.10.10 / S5c-native — receive shares from other apps.
///
/// `receive_sharing_intent` surfaces files/text the user "Share"d into
/// NaviWealth (iOS Share Extension / Android SEND intent). Each share
/// is funnelled through the existing pipeline (privacy gate → device
/// or cloud) and the user is dropped on the review queue.
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

import '../../../app/route_paths.dart';
import '../../../app/router_builder.dart';
import '../domain/ingest_models.dart';
import 'ingest_capture_source.dart';
import 'providers.dart';

class ShareIntentService {
  ShareIntentService(this._ref);

  final Ref _ref;
  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _started = false;

  /// Idempotent. Safe to call from `AppRootShell.initState`.
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
    var handled = false;
    for (final f in files) {
      try {
        final source = await _toSource(f);
        if (source == null) continue;
        await _ref.read(ingestControllerProvider).ingest(source);
        handled = true;
      } catch (_) {
        // One bad share never blocks the rest.
      }
    }
    if (handled) {
      try {
        _ref.read(appRouterProvider).go(AppRoutes.activityIngest);
      } catch (_) {}
    }
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
