# Build and publish a TradoCraft release

Use a version tag such as `v0.1.0` for the exact tested commit. Before building, align the
Rust workspace version in `Cargo.toml` with the Flutter version in `app/pubspec.yaml`.
Increase the Flutter build number for each Android update. Record the changes in `CHANGELOG.md`.

## Build candidate artifacts

In GitHub Actions, run **Release candidates** on the reviewed release ref. Configure these
repository Actions secrets for the Android job:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Release key alias |
| `ANDROID_KEY_PASSWORD` | Release key password |

Pushes to `release/v0.1.0-prep` also run the Windows and Linux builds. Android builds run on manual dispatch.

Follow [the Android signing instructions](../../app/android/README.md) to create and back up
the release key. Direct APK distribution uses this key and can be prepared without a Google
Play developer account. Reuse the same key for future APK updates. The workflow verifies the APK
signature before uploading it. Compare the signing certificate fingerprint in the build log
with your release certificate before distributing it.

Sign in to GitHub and open **Summary → Artifacts** on the workflow run. Download the artifacts
and their checksum files. The Windows x64 ZIP contains the complete unsigned Flutter application
folder and requires the Microsoft Visual C++ runtime. Extract the Linux x64 archive and run
`./tradocraft_app` from the extracted folder. The Linux bundle targets Ubuntu 24.04 x64 and
requires a graphical session and GTK 3. Verify compatibility before using another distribution.
Both desktops need a compatible TradoCraft server. For offline testing, bring any missing runtime
packages and a locally runnable server and database on the same media.

## Verify and publish

1. Complete the applicable [first release checks](../ROADMAP.md#first-release-checklist)
   on the exact release commit. Test clean installs, an APK update signed with the release key
   once a previous build exists, and both desktop bundles on the intended physical machines.
2. Verify the artifact hashes against the checksum files. Confirm the target Git commit and
   version, then create a draft GitHub release with the changelog entry.
3. Attach the verified artifacts and checksum files. Publish after approval and verify that the
   security workflow attaches the CycloneDX SBOM to the release.

The candidate workflow stores artifacts on the Actions run. GitHub Release publication is a
separate step. Prepare and verify the backend distribution before including one in the release.
