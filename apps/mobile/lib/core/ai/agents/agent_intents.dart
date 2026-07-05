/// Intent descriptors used by unified agent-result surfaces.
library;

import '../contracts/intent.dart'
    show kDomainExecution, kDomainFinance, kDomainHealth, kDomainKnowledge;
import '../intent/intent.dart';

const String kAgentArtifactObjectType = 'agent_artifact';
const String kAgentExplainResultIntent = 'agent.explainResult';
const String kAgentShowEvidenceIntent = 'agent.showEvidence';
const String kAgentCreatePlanFromResultIntent = 'agent.createPlanFromResult';
const String kFinanceReviewWealthIntent = 'finance.reviewWealth';
const String kHealthExplainRecoveryAlertIntent = 'health.explainRecoveryAlert';
const String kKnowledgeReviewDueItemsIntent = 'knowledge.reviewDueItems';

const kFinanceAgentIntentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: kAgentExplainResultIntent,
    domain: kDomainFinance,
    allowedDomains: <String>{kDomainHealth, kDomainKnowledge, kDomainExecution},
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
  IntentDescriptor(
    name: kAgentShowEvidenceIntent,
    domain: kDomainFinance,
    allowedDomains: <String>{kDomainHealth, kDomainKnowledge, kDomainExecution},
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
  IntentDescriptor(
    name: kAgentCreatePlanFromResultIntent,
    domain: kDomainFinance,
    allowedDomains: <String>{kDomainHealth, kDomainKnowledge, kDomainExecution},
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
  IntentDescriptor(
    name: kFinanceReviewWealthIntent,
    domain: kDomainFinance,
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'agent_artifacts',
      'net_worth_snapshot',
      'holdings_snapshot',
    ],
  ),
];

const kHealthAgentIntentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: kHealthExplainRecoveryAlertIntent,
    domain: kDomainHealth,
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>[
      'agent_artifacts',
      'hrv_trend',
      'recovery_signal',
    ],
  ),
];

const kKnowledgeAgentIntentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: kKnowledgeReviewDueItemsIntent,
    domain: kDomainKnowledge,
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'agent_artifacts',
      'knowledge_decisions',
      'knowledge_assumptions',
    ],
  ),
];

const kExecutionAgentIntentDescriptors = <IntentDescriptor>[];
