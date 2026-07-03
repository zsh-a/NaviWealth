/// §5.10.10 / S5c-native — receive shares from other apps.
///
/// `receive_sharing_intent` surfaces files/text the user "Share"d into
/// NaviWealth (iOS Share Extension / Android SEND intent). App code only
/// adapts plugin events into domain-neutral payloads; active domains decide
/// whether to capture a note, enqueue finance ingest, or ignore the payload.
///
/// Hard-guarded: every plugin call is wrapped so the host test VM /
/// web / desktop (no plugin registered → `MissingPluginException`)
/// is a silent no-op. The app must never crash because a share
/// channel is absent.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/lifeos/share_intent.dart';
import 'share_intent_dispatcher.dart';

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
    await _ref.read(shareIntentDispatcherProvider).dispatch([
      for (final file in files) _payloadFrom(file),
    ]);
  }

  SharedIntentPayload _payloadFrom(SharedMediaFile file) {
    return SharedIntentPayload(
      kind: switch (file.type) {
        SharedMediaType.text => SharedIntentKind.text,
        SharedMediaType.url => SharedIntentKind.url,
        SharedMediaType.image => SharedIntentKind.image,
        SharedMediaType.file => SharedIntentKind.file,
        SharedMediaType.video => SharedIntentKind.other,
      },
      value: file.path,
      mimeType: file.mimeType,
      message: file.message,
    );
  }
}

final shareIntentServiceProvider = Provider<ShareIntentService>(
  ShareIntentService.new,
);
