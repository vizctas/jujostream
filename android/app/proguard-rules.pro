# Keep JNI-callable methods in StreamingBridge — R8 cannot see calls from native C code.
-keep class com.limelight.jujostream.native_bridge.StreamingBridge {
    public static *;
}
-keepclassmembers class com.limelight.jujostream.native_bridge.StreamingBridge {
    public static *;
}

# Flutter/Play Core — suppress missing class warnings for optional Play Store modules
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication

# Flutter standard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
