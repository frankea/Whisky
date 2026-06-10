# Release Workflow

This document describes how to cut a release of the Whisky app and how to publish a new Wine Libraries archive.

The fork uses two parallel artifact streams:

- **App releases** (`app-vX.Y.Z`) — `Whisky-X.Y.Z.dmg`, signed and notarized for direct distribution.
- **Wine Libraries releases** (`vX.Y.Z`) — `Libraries.tar.gz` containing the Wine/DXVK runtime that the app downloads on first launch.

Both live on GitHub Releases. Static metadata (version plist, Sparkle appcast) is served from GitHub Pages, which is **workflow-deployed** through `.github/workflows/Documentation.yml`. The `gh-pages` branch is unused; static files go in `dist/pages/`.

## One-time setup

These only need to be done once per maintainer machine.

### Apple Developer ID Application certificate

A Developer ID Application certificate is required to ship a Gatekeeper-friendly DMG. Apple Development and Apple Distribution certs are not sufficient.

1. **Xcode → Settings → Accounts** → select your Apple ID → **Manage Certificates…**
2. Click **+** → **Developer ID Application**
3. The cert is installed in your login keychain automatically.

### notarytool credentials

Apple's notary service needs an app-specific password.

1. Generate one at <https://appleid.apple.com> → **Sign-In and Security → App-Specific Passwords**.
2. Store it as a notarytool keychain profile:
   ```sh
   xcrun notarytool store-credentials AC_PASSWORD \
     --apple-id <your-apple-id-email> \
     --team-id Z7JS58F8U3 \
     --password <app-specific-password>
   ```
3. The release script reads this profile by name (`AC_PASSWORD`).

### Sparkle EdDSA keys

A keypair is needed to sign appcast entries. Sparkle's `generate_keys` tool ships with the Sparkle SPM package; after building Whisky once, find it at:

```
~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

Run it once. The private key is stored automatically in your login keychain. The public key is printed to stdout — it is already committed in `Whisky/Info.plist` under `SUPublicEDKey`. If you regenerate keys you will invalidate the existing public key in the bundled app and need to re-release.

## Credential continuity (backup & recovery)

Three secrets gate the release pipeline. Losing the Sparkle key is **unrecoverable** for existing installs: `SUPublicEDKey` is baked into every shipped `Info.plist`, so a regenerated key permanently strands all installed copies off auto-update. Keep current, restore-tested backups of all three.

| Secret | Where it lives | If lost |
| --- | --- | --- |
| Sparkle EdDSA private key | login keychain ("Private key for signing Sparkle updates") | Existing installs never see another auto-update |
| Developer ID Application identity | login keychain | Re-issue from the Apple Developer portal; releases blocked until done |
| notarytool app-specific password | appleid.apple.com; cached as keychain profile `AC_PASSWORD` | Regenerate at appleid.apple.com, re-run `store-credentials` |

### Backup procedure

1. Export the Sparkle private key (Keychain will prompt for access):

   ```sh
   SPARKLE_BIN=$(echo ~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin)
   "$SPARKLE_BIN/generate_keys" -x sparkle_ed25519_private.key
   ```

2. Export the Developer ID identity: **Keychain Access → My Certificates** → right-click *Developer ID Application: …* → **Export** as `.p12` with a strong password.
3. Encrypt both files before they leave the machine:

   ```sh
   age -p sparkle_ed25519_private.key > sparkle_ed25519_private.key.age   # or: gpg -c <file>
   age -p developer_id.p12 > developer_id.p12.age
   ```

4. Store the encrypted files — plus the app-specific password itself — in **two** off-machine locations (e.g. a password-manager secure note and one offline medium). Delete the plaintext exports afterwards.
5. Record the certificate expiry date and set reminders at T-60 and T-14 days:

   ```sh
   security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -enddate
   ```

### Restore test (do this the day the backup is made)

A backup that has never been restored from is a hope, not a backup. `sign_update` can sign directly from a key file, so the test never touches the keychain:

```sh
"$SPARKLE_BIN/sign_update" --ed-key-file sparkle_ed25519_private.key build/release/Whisky-X.Y.Z.dmg
```

The printed `sparkle:edSignature` must exactly match that release's entry in `dist/pages/appcast.xml` — Ed25519 signatures are deterministic, so any difference means the exported key is wrong.

### Recovery on a new machine

1. Decrypt the backup, then import the Sparkle key: `generate_keys -f sparkle_ed25519_private.key`.
2. Open the `.p12` to install the Developer ID identity into the login keychain.
3. Re-create the notary profile with `xcrun notarytool store-credentials AC_PASSWORD …` (see One-time setup).

## App release

### 1. Bump versions

Update both fields in `Whisky.xcodeproj/project.pbxproj` (every occurrence):

- `MARKETING_VERSION = X.Y.Z;` — user-visible version.
- `CURRENT_PROJECT_VERSION = N;` — Sparkle build number, must increment monotonically.

### 2. Update the changelog

Move items from `[Unreleased]` to a new `[X.Y.Z] - YYYY-MM-DD (App)` section in `CHANGELOG.md`.

### 3. Build, sign, notarize, package

```sh
scripts/release.sh X.Y.Z
```

The script:

1. Archives the app (Apple Development signing during archive — automatic provisioning handles cert resolution).
2. Re-signs on export with **Developer ID Application** per `scripts/exportOptions.plist`.
3. Verifies the signature with `codesign --verify --deep --strict`.
4. Builds a UDZO disk image with `hdiutil`.
5. Signs the DMG with the Developer ID Application certificate.
6. Submits the DMG to Apple's notary service and waits for the verdict (typically 5–15 minutes).
7. Staples the notarization ticket.
8. Verifies the stapled DMG passes `spctl --assess`.

The artifact lands at `build/release/Whisky-X.Y.Z.dmg`.

### 4. Sign the DMG for Sparkle

```sh
~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update build/release/Whisky-X.Y.Z.dmg
```

Capture the printed `sparkle:edSignature` and `length`.

### 5. Add an appcast entry

Edit `dist/pages/appcast.xml` and add a new `<item>` near the top of `<channel>`. Use the signature and length from the previous step:

```xml
<item>
    <title>Whisky X.Y.Z</title>
    <pubDate>RFC822 date here</pubDate>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    <description><![CDATA[<p>Release notes...</p>]]></description>
    <enclosure
        url="https://github.com/frankea/Whisky/releases/download/app-vX.Y.Z/Whisky-X.Y.Z.dmg"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream" />
</item>
```

### 6. Commit, tag, and release

```sh
git add Whisky.xcodeproj/project.pbxproj CHANGELOG.md dist/pages/appcast.xml
git commit -m "release: X.Y.Z"
git push
git tag -a app-vX.Y.Z -m "Whisky X.Y.Z"
git push origin app-vX.Y.Z

gh release create app-vX.Y.Z \
  --repo frankea/Whisky \
  --title "Whisky X.Y.Z" \
  --notes "..." \
  build/release/Whisky-X.Y.Z.dmg
```

The push to `main` triggers `.github/workflows/Documentation.yml`, which redeploys Pages with the updated appcast within ~1–2 minutes. Sparkle clients pick up the update on next launch.

### 7. Homebrew tap (automatic)

Publishing the `app-vX.Y.Z` release fires `.github/workflows/UpdateHomebrewTap.yml`,
which downloads the DMG, computes its sha256, and bumps the
[frankea/homebrew-whisky](https://github.com/frankea/homebrew-whisky) cask so
`brew install --cask frankea/whisky/whisky` tracks the new version. No manual edit needed.

This requires a one-time repository secret **`BREW_TOKEN`** — a personal access token
(classic `repo`, or fine-grained with **Contents: write**) for `frankea/homebrew-whisky`;
the default `GITHUB_TOKEN` cannot push to another repository. If the secret is missing the
workflow fails loudly so the drift is visible. You can also re-sync any tag manually via the
workflow's `workflow_dispatch` input.

## Wine Libraries release

The runtime (`Libraries.tar.gz`) is **assembled from upstream binaries, not built from source** — see
[`DEPENDENCIES.md`](DEPENDENCIES.md) for the authoritative list of components,
their pinned versions, and where each comes from. When the runtime needs to change:

1. **Assemble `Libraries.tar.gz`** from the pinned upstream binaries. The archive unpacks to a
   `Libraries/` tree the app expects (`Libraries/Wine/bin/…` is the Wine binary dir per
   `WhiskyWineInstaller.binFolder`). To reproduce a build:
   - Download the pinned **Wine** build (Gcenx `macOS_Wine_builds`) and unpack it as `Libraries/Wine/`.
   - Add the pinned **DXVK-macOS** DLLs and **DXMT** prebuilt release into the runtime per the Gcenx
     layout.
   - Place **D3DMetal** as extracted from Apple's Game Porting Toolkit. ⚠️ Redistribution is governed by
     Apple's GPTK license — confirm terms before publishing.
   - Record the exact versions you used back into `docs/DEPENDENCIES.md`, and bump the matching
     `*_PINNED` tags in `.github/workflows/RuntimeTrack.yml` so drift detection stays accurate.
   - `tar -czf Libraries.tar.gz Libraries/` (mind the `Tar` pipe-drain pitfall noted below).
2. Tag with the bare version `vX.Y.Z` (no `app-` prefix).
3. `gh release create vX.Y.Z --title "Wine Libraries vX.Y.Z" Libraries.tar.gz`.
4. Compute the SHA-256 of the **exact published asset** — the app verifies the download against this
   and fails closed on a mismatch, so an incorrect value blocks every fresh install:
   ```sh
   shasum -a 256 Libraries.tar.gz
   ```
5. Update `dist/pages/WhiskyWineVersion.plist` with the version, bundled DXVK version, and the digest
   from the previous step. Record the same digest in [`DEPENDENCIES.md`](DEPENDENCIES.md):
   ```xml
   <dict>
       <key>version</key>
       <dict>
           <key>major</key><integer>X</integer>
           <key>minor</key><integer>Y</integer>
           <key>patch</key><integer>Z</integer>
       </dict>
       <key>dxvkVersion</key>
       <string>1.10.3</string>
       <key>sha256</key>
       <string>…64-hex-digest…</string>
   </dict>
   ```
6. Commit and push. The Documentation workflow republishes Pages, and existing app installs prompt to update on their next Wine version check.

## URLs the app depends on

- `https://frankea.github.io/Whisky/WhiskyWineVersion.plist` — Wine version metadata
- `https://frankea.github.io/Whisky/appcast.xml` — Sparkle update feed
- `https://github.com/frankea/Whisky/releases/download/vX.Y.Z/Libraries.tar.gz` — Wine binary archive
- `https://github.com/frankea/Whisky/releases/download/app-vX.Y.Z/Whisky-X.Y.Z.dmg` — app DMG

## Pitfalls

- **Don't override `CODE_SIGN_IDENTITY` at archive time.** The project is configured for Apple Development with automatic signing; overriding it conflicts with provisioning. The release script lets `xcodebuild archive` use the project default and re-signs on export.
- **Don't bundle the WhiskyKit folder as Resources.** Doing so packages the package's `.build` directory (DocC plugin executables) into the app, and Apple's notary rejects the archive because those plugin executables don't have hardened runtime. The PBXResourcesBuildPhase entry for `WhiskyKit` was removed from the project for this reason; do not add it back. The PBXFileReference and PBXGroup entries must remain or Xcode's SPM workspace integration crashes on CI.
- **Pipe deadlocks in `Tar`.** `process.waitUntilExit()` must come *after* draining the pipe, not before. The verbose tar listing for a multi-hundred-megabyte archive will overflow the OS pipe buffer. See the fix in 3.0.1.
