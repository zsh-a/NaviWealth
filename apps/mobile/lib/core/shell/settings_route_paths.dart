/// Settings shell route path and route name contract.
library;

abstract final class SettingsRoutes {
  static const root = '/settings';
  static const appearance = '/settings/appearance';
  static const devices = '/settings/devices';
  static const fxRates = '/settings/fx-rates';
  static const backup = '/settings/backup';
  static const dataManagement = '/settings/data-management';
  static const notifications = '/settings/notifications';
  static const logs = '/settings/logs';
  static const performance = '/settings/performance';
  static const developerIssues = '/settings/developer-issues';
  static const sync = '/settings/sync';
  static const ai = '/settings/ai';
  static const advanced = '/settings/advanced';
  static const dataMaintenance = '/settings/advanced/data-maintenance';
  static const aiTransparency = '/settings/ai-transparency';
  // §5.10.5 — user-facing privacy posture for provider-direct AI requests.
  static const aiPrivacy = '/settings/ai-privacy';
  // Bring-your-own LLM key for the on-device AI runtime.
  static const aiLlm = '/settings/ai-llm';
  static const aiModels = '/settings/ai-models';
  static const personalMemory = '/settings/personal-memory';
  static const agents = '/settings/agents';
  // Investment preferences — risk appetite SSOT + advanced
  // concentration thresholds.
  static const riskThresholds = '/settings/risk-thresholds';
  // Stress-test parameters for the FIRE engine.
  static const stressTest = '/settings/stress-test';
  // Monthly-expense window / override editor (powers FIRE projection).
  static const monthlyExpense = '/settings/monthly-expense';
  // LifeOS domain console — per-user opt-in toggles + per-domain ops.
  static const domains = '/settings/domains';
  static const domainsHealth = '/settings/domains/health';

  static String aiTransparencyDetail(String requestId) =>
      '$aiTransparency/${Uri.encodeComponent(requestId)}';
}

abstract final class SettingsRouteNames {
  static const root = 'settings';
  static const appearance = 'appearance';
  static const devices = 'devices';
  static const fxRates = 'fx-rates';
  static const backup = 'backup';
  static const dataManagement = 'data-management';
  static const notifications = 'notifications';
  static const logs = 'logs';
  static const performance = 'performance';
  static const developerIssues = 'developer-issues';
  static const sync = 'sync';
  static const ai = 'ai';
  static const advanced = 'advanced';
  static const dataMaintenance = 'data-maintenance';
  static const aiTransparency = 'ai-transparency';
  static const aiTransparencyDetail = 'ai-transparency-detail';
  static const aiPrivacy = 'ai-privacy';
  static const aiLlm = 'ai-llm';
  static const aiModels = 'ai-models';
  static const personalMemory = 'personal-memory';
  static const agents = 'agents';
  static const riskThresholds = 'risk-thresholds';
  static const stressTest = 'stress-test';
  static const monthlyExpense = 'monthly-expense';
  static const domains = 'domains';
  static const domainsHealth = 'domains-health';
}
