# Flutter/Firebase ProGuard Rules
# Keep Flutter and Dart classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase Auth
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firebase Firestore
-keep class com.google.firebase.firestore.** { *; }

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Prevent obfuscation of types which use MethodHandle
-keep class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Local Notifications
-keep class com.dexterous.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# General Android
-keep class androidx.** { *; }
-keep interface androidx.** { *; }

# Play Core library (required for Flutter deferred components)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Suppress warnings
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**

# Ignore missing Play Core classes (we don't use deferred components)
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
