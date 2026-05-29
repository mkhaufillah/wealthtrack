# Flutter release build ProGuard rules
# Prevents R8 from stripping network classes (OkHttp, Okio)

# Flutter/Dart HTTP client connectivity
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# OkHttp (used by Flutter on Android for network)
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep all model/serialization classes
-keep class com.filla.wealthtrack.** { *; }
