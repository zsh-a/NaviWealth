/// Barrel for `lib/core/ai/write/`. Holds the executors that turn
/// [ProposalEnvelope] subtypes into actual mutations + undo entries.
library;

export 'ai_source_mark.dart';
export 'drift_ai_touched_store.dart';
export 'drift_undo_stack.dart';
export 'interaction_mode.dart';
export 'local_immediate_executor.dart';
export 'persistent_undo_banner.dart';
export 'providers.dart';
