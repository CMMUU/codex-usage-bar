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
extension, creates a DMG, generates a SHA-256 checksum and build attestation,
and uploads the artifacts to the matching GitHub Release. Without Apple
credentials it uses an ad-hoc signature. With all Apple credentials configured,
it also submits the DMG for notarization and staples the ticket.
