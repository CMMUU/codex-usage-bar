# Release process

Production releases are built by `.github/workflows/release.yml` from semantic
version tags such as `v0.2.0`.

## Signing modes

The workflow defaults to an ad-hoc signature and does not require an Apple
Developer account. If all six secrets below are configured, it automatically
switches to Developer ID signing and Apple notarization.

## Optional GitHub Actions secrets

| Secret | Content |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_TEAM_ID` | Ten-character Apple Developer Team ID |
| `APPLE_NOTARY_KEY_BASE64` | Base64-encoded App Store Connect API `.p8` key |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

Configure either all six secrets or none of them. A partial configuration stops
the release before building. The workflow never writes credentials to the
repository or a release asset. It imports the certificate into a temporary CI
keychain and the hosted runner is discarded after the job.

In Developer ID mode, the app and widget use the macOS-only, non-provisioned
App Group identifier:

```text
<APPLE_TEAM_ID>.io.cmmuu.codex-usage-bar
```

macOS validates that the Team ID in this identifier matches the Team ID in both
code signatures. Apple documents this format in
[Accessing app group containers in your existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

Ad-hoc builds retain the default `group.io.cmmuu.codex-usage-bar` entitlement.
The menu bar app runs after the one-time Gatekeeper confirmation, while App
Group data sharing with the widget can require additional authorization on
macOS 15 and later.

## Required Sparkle signing secret

Automatic updates use a separate EdDSA key and do not require an Apple
Developer account.

| Secret | Content |
| --- | --- |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Private key exported by Sparkle `generate_keys -x` |

The matching public key is embedded in `Resources/Info.plist`. The private key
must only exist in the maintainer's macOS Keychain, an offline backup, and the
GitHub Actions secret. Never add it to the repository, logs, release notes, or
workflow arguments.

Each release signs the DMG and two separate appcasts. `appcast.xml` keeps the
GitHub enclosure URL for existing installations. `appcast-center.xml` uses the
immutable file URL on `files.cmmuu.com`. Both are uploaded to GitHub Releases;
the center verifies hashes, both feed signatures and the DMG signature before
publishing an archive. No signed content is rewritten.

Starting with v0.4.2, the app uses:

```text
https://downloads.cmmuu.com/api/releases/codex-usage-bar/appcast.xml
```

The legacy GitHub feed remains available through:

```text
https://github.com/CMMUU/codex-usage-bar/releases/latest/download/appcast.xml
```

## Publish

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Add `docs/release-notes/vX.Y.Z.md`.
3. Run the local checks:

   ```bash
   make test
   make widget-build
   make web-check
   make public-release-check
   ```

4. Push the commit and wait for CI.
5. Create and push the annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Codex Usage Bar vX.Y.Z"
   git push origin vX.Y.Z
   ```

The release workflow builds a universal app, embeds and signs the WidgetKit
extension and Sparkle framework, creates a DMG, generates a SHA-256 checksum,
produces two signed Sparkle appcasts and build attestation, and uploads the
artifacts to the matching GitHub Release. Without Apple credentials it uses an
ad-hoc signature. With all Apple credentials configured, it also submits the
DMG for notarization and staples the ticket.

## Download center publication

The registered Codex sync timer checks GitHub every five minutes. A release
contains exactly four original assets: the universal DMG, its `.sha256`,
`appcast.xml`, and `appcast-center.xml`. After GitHub publication the workflow
waits up to ten minutes for the center and verifies the exact version, all four
asset hashes, HEAD/Range responses, and byte-identical signed update feed.
A failed mirror check fails the workflow; it does not substitute an older release.

Permanent project page: `https://downloads.cmmuu.com/projects/codex-usage-bar`.
Permanent installer: `https://downloads.cmmuu.com/download/codex-usage-bar/latest/macos-universal`.
For a published version, do not rebuild or replace its signed bytes: fix any new
release issue under a new version. Operational records belong in the
[project documentation repository](https://github.com/CMMUU/project-docs).
