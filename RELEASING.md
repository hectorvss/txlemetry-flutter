# Releasing

The maintained `txlemetry_flutter` package is a 6.0.0 candidate, coordinated with Txlemetry Android and Apple SDK 4.0.0 candidates. Publication remains the last phase after all SDK migrations and validation gates pass. The imported upstream release and approval workflows are not configured for this project.

## Prepare versions and dependencies

Release metadata lives in the private pnpm workspace. Use its pinned pnpm version and checked-in lockfile, retaining the minimum release age policy. After changing the candidate version, run:

```bash
node scripts/bump-version.mjs 6.0.0
flutter pub get
```

The version script validates every expected version field before writing Dart, Kotlin, Swift, pubspec, CocoaPods, Gradle and changeset metadata. `scripts/bump-version.sh` delegates to the same implementation.

The Flutter plugin depends on the coordinated Txlemetry native SDKs. Build mobile examples against local native candidates while publication is pending. Set `TXLEMETRY_SWIFT_PACKAGE_URL` to the validated package distribution source for SwiftPM. Regenerate Apple resolution locks on an Apple build host; inherited locks pointing to the upstream SDK have been removed. Public native distribution must be validated before publishing the Flutter plugin.

## Build and validate

Run the Dart analyzer, the existing Dart and native tests, and `scripts/check-api-dart.sh` from this workspace. The API check resolves its workspace root relative to the script and compares against `api/txlemetry_flutter.api.json`; regenerate a snapshot only after reviewing the intended public API changes.

Validate Android, iOS, macOS, Windows, Linux and web builds plus the compliance adapter. Include the minimum supported Dart/Flutter and native platform versions. Verify canonical SDK identities and versions, default collector routing, events, flags, exceptions, replay, lifecycle and persisted desktop state compatibility. Native push and identity flows need their platform-specific checks.

Before publication, inspect `flutter pub publish --dry-run` output, ensure the package retains its original `LICENSE` and fork `NOTICE`, prove reproducible artifacts, and install the resulting package into clean consumers. Keep build, artifact, platform and functional evidence separate.

## Publication

Publish only after all migration and validation gates pass. The public pub.dev package and native dependencies must install without access to the private repository. Verify fresh registry installations and deployed functional flows after publication, recording versions, checksums, platforms and results. A source build or local dependency override does not prove registry installation.
