# R8/ProGuard keep rules for Viby's release build. Flutter's own rules and
# proguard-android-optimize.txt are applied in addition to these.

-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# --- just_audio → ExoPlayer / media3 (reflection on renderers/extractors) ---
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# --- audio_service (background playback service) ---
-keep class com.ryanheise.audioservice.** { *; }

# --- drift → sqlite3_flutter_libs native bindings ---
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# --- flutter_secure_storage → Tink crypto (very R8-sensitive) ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# --- on_audio_query_pluse (MediaStore queries via method channel) ---
-keep class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.on_audio_query.**

# Silence optional/annotation-only deps that R8 flags but aren't shipped.
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
