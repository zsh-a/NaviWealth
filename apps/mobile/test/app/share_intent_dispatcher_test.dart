import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/share_intents/share_intent_dispatcher.dart';
import 'package:naviwealth/app/share_intents/share_intent_navigation.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/lifeos/share_intent.dart';

const _financePath = '/finance/ingest';
const _knowledgePath = '/knowledge/inbox';

const _financeSharePack = DomainPack(
  scope: DomainScope.finance,
  shareIntentHandlers: [
    _FakeShareIntentHandler(
      acceptedKinds: {SharedIntentKind.text, SharedIntentKind.image},
      destinationPath: _financePath,
      navigationPriority: 100,
    ),
  ],
);

const _knowledgeSharePack = DomainPack(
  scope: DomainScope.knowledge,
  shareIntentHandlers: [
    _FakeShareIntentHandler(
      acceptedKinds: {SharedIntentKind.text, SharedIntentKind.url},
      destinationPath: _knowledgePath,
      dispatchPriority: 100,
    ),
  ],
);

void main() {
  test('text shares go to the higher-priority domain handler', () async {
    final destinations = <String>[];
    final c = _container(
      packs: const [_financeSharePack, _knowledgeSharePack],
      destinations: destinations,
    );
    addTearDown(c.dispose);

    await c.read(shareIntentDispatcherProvider).dispatch(const [
      SharedIntentPayload(kind: SharedIntentKind.text, value: 'reading note'),
    ]);

    expect(destinations, [_knowledgePath]);
  });

  test(
    'finance destination wins when one batch also handled finance payloads',
    () async {
      final destinations = <String>[];
      final c = _container(
        packs: const [_financeSharePack, _knowledgeSharePack],
        destinations: destinations,
      );
      addTearDown(c.dispose);

      await c.read(shareIntentDispatcherProvider).dispatch(const [
        SharedIntentPayload(kind: SharedIntentKind.text, value: 'note'),
        SharedIntentPayload(kind: SharedIntentKind.image, value: '/tmp/r.jpg'),
      ]);

      expect(destinations, [_financePath]);
    },
  );

  test('one bad payload does not block later payloads', () async {
    final destinations = <String>[];
    final c = _container(
      packs: const [
        DomainPack(
          scope: DomainScope.knowledge,
          shareIntentHandlers: [
            _FakeShareIntentHandler(
              acceptedKinds: {SharedIntentKind.text},
              destinationPath: _knowledgePath,
              dispatchPriority: 100,
              throws: true,
            ),
          ],
        ),
        _financeSharePack,
      ],
      destinations: destinations,
    );
    addTearDown(c.dispose);

    await c.read(shareIntentDispatcherProvider).dispatch(const [
      SharedIntentPayload(kind: SharedIntentKind.text, value: 'bad'),
      SharedIntentPayload(kind: SharedIntentKind.image, value: '/tmp/r.jpg'),
    ]);

    expect(destinations, [_financePath]);
  });
}

ProviderContainer _container({
  required List<DomainPack> packs,
  required List<String> destinations,
}) {
  return ProviderContainer(
    overrides: [
      activeDomainPacksProvider.overrideWith((ref) => packs),
      shareIntentNavigationSinkProvider.overrideWith((ref) => destinations.add),
    ],
  );
}

class _FakeShareIntentHandler extends DomainShareIntentHandler {
  const _FakeShareIntentHandler({
    required this.acceptedKinds,
    required this.destinationPath,
    this.navigationPriority = 0,
    this.throws = false,
    int dispatchPriority = 0,
  }) : super(priority: dispatchPriority);

  final Set<SharedIntentKind> acceptedKinds;
  final String destinationPath;
  final int navigationPriority;
  final bool throws;

  @override
  Future<DomainShareIntentResult?> handle(
    Ref ref,
    SharedIntentPayload payload,
  ) async {
    if (!acceptedKinds.contains(payload.kind)) return null;
    if (throws) throw StateError('boom');
    return DomainShareIntentResult(
      destinationPath: destinationPath,
      navigationPriority: navigationPriority,
    );
  }
}
