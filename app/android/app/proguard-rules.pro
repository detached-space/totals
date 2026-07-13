## Gson rules required by flutter_local_notifications 17.x.
# Gson reads generic type information from class-file attributes. R8 removes
# that metadata unless it is kept, which makes scheduled-notification restore
# fail with "TypeToken must be created with a type argument".
-keepattributes Signature

# Preserve annotations used by Gson adapters and serialized fields.
-keepattributes *Annotation*

# Gson can reference this JDK-internal package on supported runtimes.
-dontwarn sun.misc.**

# Preserve adapter interface information used through reflection.
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from treating fields identified by @SerializedName as unused.
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Retain TypeToken and the generic signatures of its anonymous subclasses.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
