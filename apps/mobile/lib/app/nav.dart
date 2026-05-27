// App-facing alias for the back-navigation primitives.
//
// All implementations live in
// `design_system/widgets/back_navigation.dart` so the toolbar back
// arrow, the Esc shortcut, the root system-back handler, and form
// save/delete handlers share one protocol. This file is a re-export
// kept so callers and tests can `import 'package:naviwealth/app/nav.dart'`
// — i.e. read the back primitives as an app concern, not a
// design-system one.

export '../design_system/widgets/back_navigation.dart'
    show
        attemptBack,
        clearSelectedDetail,
        hasSelectedDetail,
        kSelectedQueryKey,
        logicalParentOf,
        popOrGo,
        smartPop;
