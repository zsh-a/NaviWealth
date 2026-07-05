/// Domain-pack based dispatcher for OS share-sheet payloads.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifeos/domain_pack.dart';
import '../../core/lifeos/share_intent.dart';
import 'share_intent_navigation.dart';

class ShareIntentDispatcher {
  ShareIntentDispatcher(this._ref);

  final Ref _ref;

  Future<void> dispatch(List<SharedIntentPayload> payloads) async {
    final handlers = domainShareIntentHandlers(
      _ref.read(activeDomainPacksProvider),
    );
    if (handlers.isEmpty) return;

    DomainShareIntentResult? navigation;
    for (final payload in payloads) {
      try {
        final result = await _dispatchOne(handlers, payload);
        if (result == null) continue;
        if (navigation == null ||
            result.navigationPriority > navigation.navigationPriority) {
          navigation = result;
        }
      } catch (_) {
        // One bad share never blocks the rest of the batch.
      }
    }

    final destinationPath = navigation?.destinationPath;
    if (destinationPath == null) return;
    _navigate(destinationPath);
  }

  Future<DomainShareIntentResult?> _dispatchOne(
    List<DomainShareIntentHandler> handlers,
    SharedIntentPayload payload,
  ) async {
    for (final handler in handlers) {
      final result = await handler.handle(_ref, payload);
      if (result != null) return result;
    }
    return null;
  }

  void _navigate(String destinationPath) {
    try {
      _ref.read(shareIntentNavigationSinkProvider)(destinationPath);
    } catch (_) {}
  }
}

final shareIntentDispatcherProvider = Provider<ShareIntentDispatcher>(
  ShareIntentDispatcher.new,
);
