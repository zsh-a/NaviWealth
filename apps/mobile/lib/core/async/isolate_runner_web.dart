import 'dart:async';

Future<T> runInIsolate<T>(T Function() computation) async {
  await Future<void>.delayed(Duration.zero);
  return computation();
}
