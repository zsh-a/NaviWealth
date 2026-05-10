import 'dart:async';
import 'dart:isolate';

Future<T> runInIsolate<T>(T Function() computation) => Isolate.run(computation);
