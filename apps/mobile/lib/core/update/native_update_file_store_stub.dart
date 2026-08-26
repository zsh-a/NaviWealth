import 'package:dio/dio.dart';

abstract interface class NativeUpdateFileStore {
  Future<String> download({
    required Dio dio,
    required Uri url,
    required String versionKey,
    void Function(int received, int total)? onProgress,
  });

  Future<String> sha256File(String path);

  Future<void> delete(String path);
}

NativeUpdateFileStore createNativeUpdateFileStore() =>
    const _UnsupportedNativeUpdateFileStore();

final class _UnsupportedNativeUpdateFileStore implements NativeUpdateFileStore {
  const _UnsupportedNativeUpdateFileStore();

  @override
  Future<String> download({
    required Dio dio,
    required Uri url,
    required String versionKey,
    void Function(int received, int total)? onProgress,
  }) => Future<String>.error(
    UnsupportedError('Native APK updates are unavailable on this platform'),
  );

  @override
  Future<String> sha256File(String path) => Future<String>.error(
    UnsupportedError('Native APK updates are unavailable on this platform'),
  );

  @override
  Future<void> delete(String path) => Future<void>.value();
}
