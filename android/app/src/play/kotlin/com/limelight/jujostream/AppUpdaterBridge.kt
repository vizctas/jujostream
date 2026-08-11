package com.limelight.jujostream

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

internal object AppUpdaterBridge {
    fun register(activity: FlutterActivity, flutterEngine: FlutterEngine) {
        // Play owns updates. No installer channel is registered in this artifact.
    }
}
