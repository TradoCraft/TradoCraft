# Android release signing

A release build that anybody installs must be signed with a production key that only the owner
holds. The Gradle build (`app/build.gradle.kts`) has **no debug-key fallback**: `assembleRelease`,
`bundleRelease`, `flutter build apk --release` and `flutter build appbundle --release` fail with
"Release signing is not configured" when no release key is set. Debug builds still use the debug key.

> **WARNING: never distribute a debug-signed build.** The debug key is public; anybody can sign a
> malicious update that installs over your app. Do not upload, mail or publish such an APK/AAB.

## 1. Create the production key (owner, once)

Do this on a trusted machine, never in CI, and never commit the result.

```bash
keytool -genkeypair -v \
  -keystore ~/tradocraft-release.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias tradocraft
```

`keytool` asks for the store password, the key password and the certificate owner. Back the file and
the passwords up in a password manager or vault: a lost key means no more updates for existing
installations. Enrol in Play App Signing if you publish on Google Play (this key then becomes the
upload key).

## 2. Local release builds

Create `app/android/key.properties` (git-ignored, as are `*.jks` and `*.keystore`):

```properties
storeFile=/home/you/tradocraft-release.jks
storePassword=...
keyAlias=tradocraft
keyPassword=...
```

Then, from `app/`: `flutter build apk --release` or `flutter build appbundle --release`.

Instead of the file you can set `ANDROID_KEYSTORE_FILE`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`; `key.properties` takes precedence.

## 3. CI: `.github/workflows/android-release.yml`

Runs on a `v*` tag and on manual dispatch, builds a signed AAB and APK and uploads them as workflow
artifacts. Create these repository (or environment) secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/tradocraft-release.jks` (macOS: `base64 -i file`) |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `tradocraft` (the alias used above) |
| `ANDROID_KEY_PASSWORD` | the key password |

The workflow fails with a clear message when any of them is missing.

## 4. Verify that a build is not debug-signed

```bash
# Build tools from the Android SDK: $ANDROID_HOME/build-tools/<version>/apksigner
apksigner verify --print-certs app-release.apk
```

Check the certificate: it must show your own owner name and a SHA-256 digest that matches
`keytool -list -v -keystore ~/tradocraft-release.jks -alias tradocraft`. If it says
`CN=Android Debug, O=Android, C=US` it is the debug key: delete the build, do not distribute it.
For an AAB use `jarsigner -verify -verbose -certs app-release.aab` or
`keytool -printcert -jarfile app-release.aab`.
