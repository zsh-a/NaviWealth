/// Intent descriptors used by unified agent-result surfaces.
library;

import '../intent/intent.dart';

const String kAgentArtifactObjectType = 'agent_artifact';
const String kAgentExplainResultIntent = 'agent.explainResult';
const String kAgentShowEvidenceIntent = 'agent.showEvidence';
const String kAgentCreatePlanFromResultIntent = 'agent.createPlanFromResult';
const String kFinanceReviewWealthIntent = 'finance.reviewWealth';
const String kHealthExplainRecoveryAlertIntent = 'health.explainRecoveryAlert';

const kAgentResultIntentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: kAgentExplainResultIntent,
    domain: AiDomain.shell(),
    allowedDomains: <AiDomain>[
      AiDomain.global(),
      AiDomain.domain(DomainScope.finance),
      AiDomain.domain(DomainScope.health),
      AiDomain.domain(DomainScope.knowledge),
      AiDomain.domain(DomainScope.execution),
    ],
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
  IntentDescriptor(
    name: kAgentShowEvidenceIntent,
    domain: AiDomain.shell(),
    allowedDomains: <AiDomain>[
      AiDomain.global(),
      AiDomain.domain(DomainScope.finance),
      AiDomain.domain(DomainScope.health),
      AiDomain.domain(DomainScope.knowledge),
      AiDomain.domain(DomainScope.execution),
    ],
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
  IntentDescriptor(
    name: kAgentCreatePlanFromResultIntent,
    domain: AiDomain.shell(),
    allowedDomains: <AiDomain>[
      AiDomain.global(),
      AiDomain.domain(DomainScope.finance),
      AiDomain.domain(DomainScope.health),
      AiDomain.domain(DomainScope.knowledge),
      AiDomain.domain(DomainScope.execution),
    ],
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>['agent_artifacts', 'agent_runs'],
  ),
];

const kFinanceAgentIntentDescriptors = <IntentDescriptor>[
  ...kAgentResultIntentDescriptors,
  IntentDescriptor(
    name: kFinanceReviewWealthIntent,
    domain: AiDomain.domain(DomainScope.finance),
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
  ...kAgentResultIntentDescriptors,
  IntentDescriptor(
    name: kHealthExplainRecoveryAlertIntent,
    domain: AiDomain.domain(DomainScope.health),
    allowedObjectTypes: <String>{kAgentArtifactObjectType},
    preferredCapabilities: <AiCapability>{AiCapability.chat},
    preferredReadModels: <String>[
      'agent_artifacts',
      'hrv_trend',
      'recovery_signal',
    ],
  ),
];

const kExecutionAgentIntentDescriptors = <IntentDescriptor>[
  ...kAgentResultIntentDescriptors,
];
