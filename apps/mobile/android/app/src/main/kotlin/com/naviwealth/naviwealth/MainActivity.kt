package com.naviwealth.naviwealth

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var speechBridge: AndroidSpeechBridge? = null
    private var audioCaptureBridge: AndroidAudioCaptureBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speechBridge = AndroidSpeechBridge(this).also { it.attach(flutterEngine) }
        audioCaptureBridge = AndroidAudioCaptureBridge(this).also { it.attach(flutterEngine) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (speechBridge?.onRequestPermissionsResult(requestCode, grantResults) != true &&
            audioCaptureBridge?.onRequestPermissionsResult(requestCode, grantResults) != true
        ) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onStop() {
        speechBridge?.onHostStopped()
        audioCaptureBridge?.onHostStopped()
        super.onStop()
    }

    override fun onDestroy() {
        speechBridge?.dispose()
        speechBridge = null
        audioCaptureBridge?.dispose()
        audioCaptureBridge = null
        super.onDestroy()
    }
}
