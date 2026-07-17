package com.naviwealth.naviwealth

import android.content.Context
import android.util.Log
import io.flutter.app.FlutterApplication

/** Process-level native initialization for UI and background entry points. */
class NaviWealthApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        initNativeRuntime()
    }

    private fun initNativeRuntime() {
        try {
            System.loadLibrary("lifeos_native")
            if (!initLifeosNativeAndroid(applicationContext)) {
                Log.e(TAG, "lifeos_native Android initialization returned false")
            }
        } catch (error: UnsatisfiedLinkError) {
            Log.e(TAG, "lifeos_native library is unavailable", error)
        } catch (error: RuntimeException) {
            Log.e(TAG, "lifeos_native Android initialization failed", error)
        }
    }

    private external fun initLifeosNativeAndroid(context: Context): Boolean

    companion object {
        private const val TAG = "NaviWealthApplication"
    }
}
