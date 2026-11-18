package com.longbridge.nsh;

import android.app.Activity;
import android.content.Context;

/** Keeps the same standalone limits and edge-to-edge setup as the pinned NSH runner. */
public final class NaviStandalone extends NshView {
    public NaviStandalone(Context context) {
        super(context);
        useStandaloneLimits();
    }
    public static void configure(Activity activity) { DevActivity.edgeToEdge(activity); }
    public static void configurationChanged(Activity activity) { DevActivity.systemBars(activity); }
    public void loadNaviWealth() { loadAssetBundle("nsh", true); }
}
