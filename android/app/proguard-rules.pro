-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class com.google.android.gms.** { *; }

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# video_player
-keep class io.flutter.plugins.videoplayer.** { *; }

# gal (갤러리 저장)
-keep class jp.co.gal.** { *; }

-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
