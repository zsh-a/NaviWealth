import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

late StreamController<int> _values;

final _streamValueProvider = AsyncNotifierProvider<_StreamValueNotifier, int>(
  _StreamValueNotifier.new,
);

final _derivedValueProvider = Provider<int>(
  (ref) => ref.watch(_streamValueProvider).value ?? 0,
);

final _displayValueProvider = Provider<int>(
  (ref) => ref.watch(_derivedValueProvider),
);

class _StreamValueNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() {
    final stream = _values.stream;
    final subscription = stream.listen((value) => state = AsyncData(value));
    ref.onDispose(subscription.cancel);
    return stream.first;
  }
}

class _ResumeHarness extends ConsumerStatefulWidget {
  const _ResumeHarness();

  @override
  ConsumerState<_ResumeHarness> createState() => _ResumeHarnessState();
}

class _ResumeHarnessState extends ConsumerState<_ResumeHarness> {
  bool _showValue = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _showValue = !_showValue),
            child: const Text('toggle'),
          ),
          if (_showValue) Text('${ref.watch(_displayValueProvider)}'),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('resuming a paused provider chain is build-phase safe', (
    tester,
  ) async {
    _values = StreamController<int>.broadcast(sync: true);
    addTearDown(_values.close);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _ResumeHarness())),
    );

    _values.add(1);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('toggle'));
    await tester.pump();
    _values.add(2);
    await tester.pump();

    await tester.tap(find.text('toggle'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
  });
}
