# Keep Flutter engine/bootstrap classes used by generated code and plugins.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep WebRTC classes referenced by plugin/JNI.
-keep class org.webrtc.** { *; }

# Keep audioplayers classes referenced reflectively by plugin internals.
-keep class xyz.luan.audioplayers.** { *; }
