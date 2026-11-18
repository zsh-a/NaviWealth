package com.naviwealth.app

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import com.longbridge.nsh.NaviStandalone

/** Android owns hardware and lifecycle; the existing UI and domain core stay in NSH/Rust. */
class MainActivity : Activity() {
    private lateinit var nsh: NaviStandalone
    private lateinit var ble: ScaleBleBridge

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        NaviStandalone.configure(this)
        nsh = NaviStandalone(this)
        ble = ScaleBleBridge(this, nsh)
        setContentView(nsh)
        nsh.handleNotificationIntent(intent)
        if (state == null) nsh.handleUrlSchemeIntent(intent)
        // Handlers exist before evaluating the TSX bundle.
        nsh.loadNaviWealth()
    }

    override fun onStart() { super.onStart(); if (::ble.isInitialized) ble.onForeground() }
    override fun onStop() { if (::ble.isInitialized) ble.onBackground(); super.onStop() }
    override fun onDestroy() {
        if (::ble.isInitialized) ble.destroy()
        if (::nsh.isInitialized) nsh.destroy()
        super.onDestroy()
    }
    override fun onConfigurationChanged(config: Configuration) {
        super.onConfigurationChanged(config)
        NaviStandalone.configurationChanged(this)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        nsh.handleNotificationIntent(intent)
        nsh.handleUrlSchemeIntent(intent)
    }
    @Suppress("DEPRECATION")
    @Deprecated("Android 12 and earlier back handling")
    override fun onBackPressed() { if (!nsh.handleBack()) super.onBackPressed() }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (::ble.isInitialized) ble.onPermissionResult(code)
    }
}
