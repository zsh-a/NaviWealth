import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
    const IoNativeUpdateFileStore();

final class IoNativeUpdateFileStore implements NativeUpdateFileStore {
  const IoNativeUpdateFileStore();

  @override
  Future<String> download({
    required Dio dio,
    required Uri url,
    required String versionKey,
    void Function(int received, int total)? onProgress,
  }) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final updatesDirectory = Directory(
      path.join(temporaryDirectory.path, 'naviwealth-updates'),
    );
    await updatesDirectory.create(recursive: true);

    final assetName = path.basename(url.path).isEmpty
        ? 'naviwealth-update.apk'
        : path.basename(url.path);
    final safeVersion = versionKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final safeAsset = assetName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final output = File(
      path.join(updatesDirectory.path, 'update-$safeVersion-$safeAsset'),
    );
    if (await output.exists()) await output.delete();

    try {
      await dio.download(
        url.toString(),
        output.path,
        deleteOnError: true,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          headers: const <String, Object>{
            'Accept': 'application/vnd.android.package-archive',
          },
        ),
      );
    } on Object {
      if (await output.exists()) await output.delete();
      rethrow;
    }

    if (!await output.exists() || await output.length() == 0) {
      throw const FormatException('GitHub returned an empty APK');
    }
    return output.path;
  }

  @override
  Future<String> sha256File(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FileSystemException('Downloaded APK is missing');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}
