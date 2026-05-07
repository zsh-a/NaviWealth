import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../core/logging/app_logger.dart';

@JS('window')
external JSObject get _window;

Future<bool> saveBackupFileImpl(Uint8List bytes, String fileName) async {
  AppLogger.instance.d(
    'file_saver: web download triggered — '
    '$fileName (${bytes.length} bytes)',
  );
  final blob = web.Blob(
    [bytes.buffer.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );

  if (_window.hasProperty('showSaveFilePicker'.toJS).toDart) {
    try {
      final handle =
          await (_window.callMethodVarArgs('showSaveFilePicker'.toJS, [
                    {
                      'suggestedName': fileName,
                      'types': [
                        {
                          'description': 'NaviWealth backup',
                          'accept': {
                            'application/octet-stream': ['.bak'],
                          },
                        },
                      ],
                    }.jsify(),
                  ])
                  as JSPromise<JSAny?>)
              .toDart;
      if (handle != null) {
        final writable =
            await ((handle as JSObject).callMethodVarArgs(
                      'createWritable'.toJS,
                      <JSAny?>[],
                    )
                    as JSPromise<JSAny?>)
                .toDart;
        if (writable != null) {
          await ((writable as JSObject).callMethodVarArgs('write'.toJS, [blob])
                  as JSPromise<JSAny?>)
              .toDart;
          await (writable.callMethodVarArgs('close'.toJS, <JSAny?>[])
                  as JSPromise<JSAny?>)
              .toDart;
          AppLogger.instance.i('file_saver: saved via File System Access API');
          return true;
        }
      }
    } catch (e) {
      AppLogger.instance.d(
        'file_saver: File System Access API unavailable/cancelled ($e), '
        'falling back to download',
      );
    }
  }

  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return true;
}
