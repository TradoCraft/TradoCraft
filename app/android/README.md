# Android release signing

A release build that people install must be signed with a key of your own, kept private. Without
`key.properties` the release is signed with the public debug key (a warning is printed) and must not
be distributed.

1. Create a key once and keep the file safe and backed up (a lost key means no more updates):

   ```bash
   keytool -genkey -v -keystore ~/tradocraft-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tradocraft
   ```

2. Create `app/android/key.properties` (it is git-ignored; never commit it or the keystore):

   ```properties
   storeFile=/home/you/tradocraft-release.jks
   storePassword=...
   keyAlias=tradocraft
   keyPassword=...
   ```

3. `flutter build apk --release` (or `appbundle`) from `app/`.
