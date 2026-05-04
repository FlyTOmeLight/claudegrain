# Release Playbook — v0.1.0

End-to-end checklist for cutting a public release.

## 0. Prereqs

- Apple Developer Program account (paid, $99/y)
- Developer ID Application certificate enrolled in your local Keychain
- App Store Connect API key (issuer ID + key ID + .p8 private key)
- GitHub repo created (e.g. `claudegrain/claudegrain` or `Artzainnn/claudegrain`)

## 1. Configure local notarization

```bash
# one-time: store credentials in keychain so notarytool can use them
xcrun notarytool store-credentials "claudegrain-notary" \
  --apple-id "you@example.com" \
  --team-id "ABCDEFGHIJ" \
  --password "app-specific-password"
```

## 2. Local release build (test before pushing tag)

```bash
DEVELOPER_ID="Developer ID Application: Your Name (ABCDEFGHIJ)" \
NOTARY_PROFILE="claudegrain-notary" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
bash scripts/build-dmg.sh
```

Verify:
```bash
spctl -a -t exec -vv dist/claudegrain.app
xcrun stapler validate dist/claudegrain.app
hdiutil verify dist/claudegrain-0.1.0.dmg
```

Expect `accepted source=Notarized Developer ID` and stapler `100% valid`.

## 3. Configure GitHub repo secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of the Developer ID `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | password protecting the `.p12` |
| `DEVELOPER_ID` | identity string, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_API_KEY_ID` | App Store Connect key ID |
| `NOTARY_API_KEY_ISSUER_ID` | issuer UUID |
| `NOTARY_API_KEY_PRIVATE_KEY_BASE64` | base64 of `.p8` private key |

Encode the .p12 / .p8 files:
```bash
base64 -i Certificates.p12 | pbcopy        # paste into DEVELOPER_ID_CERT_P12_BASE64
base64 -i AuthKey_XXXXXXXXX.p8 | pbcopy    # paste into NOTARY_API_KEY_PRIVATE_KEY_BASE64
```

## 4. Tag & push

```bash
git tag v0.1.0
git push origin main --follow-tags
```

GitHub Actions release.yml runs on the `v*` tag, builds the DMG with full
Developer ID signing + notarization + stapling, then creates a Release with
the DMG attached.

## 5. Verify the published Release

- Download the DMG from the Releases page
- Mount it on a separate Mac that has never seen this app
- Drag claudegrain.app to /Applications/
- Right-click → Open (first launch) — Gatekeeper should accept silently
- Confirm the menu bar icon shows up after a few seconds
- Open Settings (Cmd+,) → toggle "Open at login" off then on
- Verify OAuth path: Settings should show "OAuth ✓" data source

## 6. Post-release

- Submit to Homebrew Cask: open a PR against
  `Homebrew/homebrew-cask` with a `claudegrain.rb` cask file pointing at the
  GitHub Releases DMG URL
- Tweet / Show HN announcing the release
- Tag next milestone in CHANGELOG (Unreleased section)

## Rollback

If a release ships broken:

```bash
gh release delete v0.1.0 --cleanup-tag
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
```

Then fix, bump VERSION, re-tag.
