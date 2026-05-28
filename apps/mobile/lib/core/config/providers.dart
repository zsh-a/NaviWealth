import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Active app config. Override at the root `ProviderScope` to switch envs
/// in flavor builds (e.g. staging entrypoint).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.dev);
