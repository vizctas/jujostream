# Keep JNI-callable methods in StreamingBridge — R8 cannot see calls from native C code.
-keep class com.limelight.jujostream.native_bridge.StreamingBridge {
    public static *;
}
-keepclassmembers class com.limelight.jujostream.native_bridge.StreamingBridge {
    public static *;
}

# Keep PairingForegroundService — launched via Intent from MainActivity.
# R8 cannot trace the dynamic service start and will strip it otherwise.
-keep class com.limelight.jujostream.native_bridge.PairingForegroundService { *; }
-keep class com.limelight.jujostream.native_bridge.NativePairingResult { *; }

# Flutter/Play Core — suppress missing class warnings for optional Play Store modules
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication

# Flutter standard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
