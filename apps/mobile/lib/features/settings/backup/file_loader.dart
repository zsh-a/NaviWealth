import 'dart:typed_data';

import 'file_loader_stub.dart' if (dart.library.io) 'file_loader_native.dart';

Future<Uint8List?> readPickedFileBytes(String? path) =>
    readPickedFileBytesImpl(path);
