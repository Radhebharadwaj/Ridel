# ==========================================
# FLUTTER RULES
# ==========================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ==========================================
# MAPLIBRE & OLA MAPS RULES (To prevent map crash)
# ==========================================
-keep class org.maplibre.gl.** { *; }
-keep class org.maplibre.gl.annotations.** { *; }
-keep class org.maplibre.gl.geometry.** { *; }
-keep class org.maplibre.gl.style.layers.** { *; }
-keep class org.maplibre.gl.style.sources.** { *; }
-keep class com.ola.maps.** { *; }
-keep class com.ola.navigation.** { *; }

# ==========================================
# MOENGAGE RULES
# ==========================================
-keep class com.moengage.** { *; }
-dontwarn com.moengage.**

# ==========================================
# ANDROID X & MATERIAL DESIGN
# ==========================================
-keep class com.google.android.material.** { *; }
-keep class androidx.** { *; }
-dontwarn androidx.**

# ==========================================
# IGNORE MISSING CLASSES (R8 STRICTNESS FIX)
# ==========================================

# 1. Flutter Play Core Deferred Components (Optional hote hain, R8 ko ignore karne bole)
-dontwarn com.google.android.play.core.**

# 2. Ola Maps SDK Compiler/Annotation Dependencies (Runtime par inki zaroorat nahi hoti)
-dontwarn com.ryanharter.auto.value.gson.**
-dontwarn javax.lang.model.**
-dontwarn javax.tools.**
-dontwarn com.squareup.javapoet.**