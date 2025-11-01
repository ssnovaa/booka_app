#############################
# Flutter / Embedding
#############################
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.app.** { *; }
-dontwarn io.flutter.**

#############################
# Firebase / Google Play services
#############################
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# FCM (на всякий)
-keep class com.google.firebase.messaging.** { *; }

#############################
# WorkManager (транзитивно у FCM)
#############################
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

#############################
# just_audio / Media3 / ExoPlayer
#############################
# Новый стек AndroidX Media3
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Старый пакет ExoPlayer (если где-то тянется)
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Совместимость media-compat (иногда нужны уведомления/сессии)
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**

# Плагины Райана (just_audio*, audio_service, just_audio_background)
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

#############################
# Gson (если используешь аннотации @SerializedName)
#############################
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keepattributes *Annotation*,Signature

#############################
# Kotlin / Coroutines / Metadata
#############################
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**
-keep class kotlin.Metadata { *; }
-keepattributes InnerClasses,EnclosingMethod,Signature,SourceFile,LineNumberTable,*Annotation*

#############################
# OkHttp / Okio (часто тянут плагины/FB)
#############################
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

#############################
# AndroidX (общие предупреждения)
#############################
-dontwarn androidx.**

# Иногда Media3 тянет аннотации из Checker Framework / Error Prone — заглушим варнинги:
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.**
-dontwarn com.google.j2objc.annotations.**
