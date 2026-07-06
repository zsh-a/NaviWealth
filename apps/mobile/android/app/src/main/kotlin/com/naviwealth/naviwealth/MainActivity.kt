package com.naviwealth.naviwealth

import android.content.Context
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        initNativeTlsVerifier()
        super.onCreate(savedInstanceState)
    }

    private fun initNativeTlsVerifier() {
        try {
            System.loadLibrary("lifeos_native")
            if (!initLifeosNativeAndroid(applicationContext)) {
                Log.e(TAG, "lifeos_native Android TLS verifier initialization returned false")
            }
        } catch (error: UnsatisfiedLinkError) {
            Log.e(TAG, "lifeos_native library is unavailable", error)
        } catch (error: RuntimeException) {
            Log.e(TAG, "lifeos_native Android TLS verifier initialization failed", error)
        }
    }

    private external fun initLifeosNativeAndroid(context: Context): Boolean

    companion object {
        private const val TAG = "MainActivity"
    }
}
