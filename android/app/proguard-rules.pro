# Shizuku (Wajib Keep karena diakses via Reflection/Binder)
-keep class rikka.shizuku.** { *; }
-keep interface rikka.shizuku.** { *; }
-keep class moe.shizuku.api.** { *; }

# Suppress warnings for Play Core (Dynamic Features)
# Kita tidak menggunakan fitur ini, jadi abaikan referensi yang hilang
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.app.**

# Flutter Plugins
-keep class io.flutter.plugins.** { *; }
-keep class com.santhoshDsubramani.shizuku_api.** { *; }
