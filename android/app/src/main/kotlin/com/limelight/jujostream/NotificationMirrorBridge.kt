package com.limelight.jujostream

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NotificationMirrorBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    fun attach(sink: EventChannel.EventSink?) {
        mainHandler.post { eventSink = sink }
    }

    fun detach() {
        mainHandler.post { eventSink = null }
    }

    fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }
}
