import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'intent_policy.dart';

/// Active intent catalog assembled by app/domain composition.
///
/// Core defaults to empty so tests and shell-only builds do not accidentally
/// advertise Finance intents. Production overrides this from active
/// DomainPack entries.
final intentCatalogProvider = Provider<IntentCatalog>(
  (ref) => IntentCatalog.empty,
);
