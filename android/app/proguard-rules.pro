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
# just_audio / ExoPlayer
#############################
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

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
