// NaviWealth custom Flutter web bootstrap.
//
// Replaces the auto-generated flutter_bootstrap.js so the build no longer
// depends on the deprecated `--pwa-strategy` flag (flutter/flutter#156910).
//
// `_flutter.loader.load()` is called with NO serviceWorkerSettings, so
// Flutter never registers its own flutter_service_worker.js. This app
// ships a hand-written web/service_worker.js, registered from index.html.
//
// The Flutter loader and build config placeholders below are substituted by
// the Flutter web build at compile time.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
