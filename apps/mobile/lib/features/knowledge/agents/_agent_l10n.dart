/// Locale helpers for KnowledgeOS agents.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent_l10n.dart';
import '../../../l10n/gen/app_localizations.dart';

AppLocalizations knowledgeAgentL10n(Ref ref) => agentL10n(ref);
