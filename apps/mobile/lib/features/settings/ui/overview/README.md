# Settings Overview UI

Settings landing-page sections live here. Keep `settings_page.dart` as the
route-level wrapper in `features/settings/ui/`; section composition and row
groups belong in this directory.

Keep settings focused on user configuration. Local product funnel counters and
their export action were removed together with the collector and call sites;
Agent quality aggregates were removed from Advanced. Operational logs, runtime
traces and opt-in crash reporting remain available for actual troubleshooting.

Appearance no longer exposes the Classic/Refined preview picker. Previously
saved visual presets still resolve for compatibility; theme, accent, material,
language and market-color controls retain their existing behavior. AI settings
also omits the conversation shortcut: the shared assistant surface owns chat
and history navigation.
