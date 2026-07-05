import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/routing/route_analytics_observer.dart';

class _RecordingSink implements PageViewSink {
  final List<PageViewEvent> events = <PageViewEvent>[];

  @override
  void recordPageView(PageViewEvent event) => events.add(event);
}

MaterialPageRoute<void> _route(String name) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox.shrink(),
  );
}

void main() {
  late _RecordingSink sink;
  late RouteAnalyticsObserver observer;

  setUp(() {
    sink = _RecordingSink();
    observer = RouteAnalyticsObserver(sink);
  });

  test('didPush emits a page_view event with the route name', () {
    observer.didPush(_route('home'), null);
    expect(sink.events, hasLength(1));
    expect(sink.events.single.name, 'home');
    expect(sink.events.single.previousName, isNull);
    expect(sink.events.single.transition, 'push');
  });

  test('didPush includes the previous route name', () {
    observer.didPush(_route('assets'), _route('home'));
    expect(sink.events.single.previousName, 'home');
    expect(sink.events.single.transition, 'push');
  });

  test('didPop reports the route the user is returning to', () {
    observer.didPop(_route('detail'), _route('assets'));
    final event = sink.events.single;
    // When `detail` pops, `assets` becomes visible — that's the page view.
    expect(event.name, 'assets');
    expect(event.previousName, 'detail');
    expect(event.transition, 'pop');
  });

  test('didReplace emits using the new route', () {
    observer.didReplace(newRoute: _route('login'), oldRoute: _route('home'));
    final event = sink.events.single;
    expect(event.name, 'login');
    expect(event.previousName, 'home');
    expect(event.transition, 'replace');
  });

  test('anonymous routes (e.g. dialogs) are skipped', () {
    final dialog = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    observer.didPush(dialog, _route('home'));
    expect(sink.events, isEmpty);
  });

  test('didReplace with no new route is a no-op', () {
    observer.didReplace(oldRoute: _route('home'));
    expect(sink.events, isEmpty);
  });
}
