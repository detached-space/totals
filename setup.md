# Branch Setup Notes (pubspec/android behind)

apply the following minimal changes so the newer notification + categories features compile and run.

## 1) `pubspec.yaml`

Add these dependencies (versions can match your branch, but these are known-good here):

```yaml
dependencies:
  shared_preferences: ^2.2.3
  flutter_local_notifications: ^18.0.1
  permission_handler: ^11.3.1
  workmanager: ^0.7.0
```

Then run:

```bash
flutter pub get
```

## 2) Android: enable desugaring (required by `flutter_local_notifications`)

Edit `android/app/build.gradle`:

- In `android { compileOptions { ... } }` enable desugaring:

```gradle
compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
    coreLibraryDesugaringEnabled true
}
```

- Add the desugaring dependency:

```gradle
dependencies {
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"
}
```

Also make sure `minSdkVersion` is at least **23** in the same file.

## 3) Android: notification permission (Android 13+)

Edit `android/app/src/main/AndroidManifest.xml` and ensure this permission exists:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```
