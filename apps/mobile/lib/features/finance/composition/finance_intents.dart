/// FinanceOS intent contributions for AI object capsules and invocation
/// surfaces.
library;

import '../../../core/ai/intent/intent.dart';

const kFinanceIntentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: 'explain_change',
    allowedObjectTypes: <String>{
      'expense',
      'recurring_pattern',
      'asset',
      'liability',
      'account',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'subscription_changes',
      'recurring_patterns',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'summarize_account',
    allowedObjectTypes: <String>{'account'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'holdings_snapshot',
      'cashflow_buckets',
      'investment_performance',
    ],
  ),
  IntentDescriptor(
    name: 'stress_test_plan',
    allowedObjectTypes: <String>{'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'holdings_snapshot',
      'investment_performance',
    ],
  ),
  IntentDescriptor(
    name: 'compare_period',
    allowedObjectTypes: <String>{
      'expense',
      'account',
      'asset',
      'recurring_pattern',
    },
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>['cashflow_buckets'],
  ),
  IntentDescriptor(
    name: 'explain_insight',
    allowedObjectTypes: <String>{'insight'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>[
      'anomaly_flags',
      'subscription_changes',
      'refund_links',
    ],
  ),
  IntentDescriptor(
    name: 'explain_chart',
    allowedObjectTypes: <String>{'chart'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'net_worth_snapshot',
      'cashflow_buckets',
      'holdings_snapshot',
    ],
  ),
  IntentDescriptor(
    name: 'transactions.explainSelection',
    allowedObjectTypes: <String>{'transactions'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'cashflow_buckets',
      'subscription_changes',
      'refund_links',
    ],
  ),
  IntentDescriptor(
    name: 'explain_fire_state',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>[
      'fire_state',
      'net_worth_snapshot',
      'cashflow_buckets',
    ],
  ),
  IntentDescriptor(
    name: 'review_cash_bucket',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>['fire_state'],
  ),
  IntentDescriptor(
    name: 'simulate_fire_change',
    allowedObjectTypes: <String>{'fire_plan', 'fire_state'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    // `simulate_fire_plan` does not start with `get_` so the corpus
    // normaliser does not strip it; list it verbatim.
    preferredReadModels: <String>[
      'fire_state',
      'fire_plan',
      'simulate_fire_plan',
    ],
  ),
  IntentDescriptor(
    name: 'explain_stress_test',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.visualization,
    },
    preferredReadModels: <String>['fire_state', 'fire_stress_tests'],
  ),
  IntentDescriptor(
    name: 'suggest_fire_actions',
    allowedObjectTypes: <String>{'fire_state', 'fire_plan'},
    preferredCapabilities: <AiCapability>{
      AiCapability.chat,
      AiCapability.proposal,
    },
    preferredReadModels: <String>['fire_state', 'fire_stress_tests'],
  ),
];
