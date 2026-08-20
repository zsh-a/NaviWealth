import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:naviwealth/src/rust/frb_generated.dart' show RustLib;

Future<void> loadLifeosNativeRuntime({String? libraryPath}) {
  if (libraryPath != null && libraryPath.isNotEmpty) {
    return RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  }
  return RustLib.init();
}
