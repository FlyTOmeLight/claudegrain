# Release scripts

## `build-dmg.sh`

Builds `claudegrain` in release, wraps it in a `claudegrain.app` menu bar bundle
(`LSUIElement=true`), code-signs, packages a DMG, and notarizes/staples.

### Output

- `dist/claudegrain.app`
- `dist/claudegrain-<version>.dmg`

Version is read from `VERSION` at the repo root.

### Local usage

```sh
# Unsigned, ad-hoc build (will not pass Gatekeeper, fine for smoke testing).
./scripts/build-dmg.sh

# Signed + notarized release.
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="claudegrain-notary"   # set up once via `xcrun notarytool store-credentials`
./scripts/build-dmg.sh
```

### Environment variables

| Var              | Required | Purpose                                                                 |
|------------------|----------|-------------------------------------------------------------------------|
| `DEVELOPER_ID`   | release  | Codesign identity. If unset, the app is signed ad-hoc with a warning.   |
| `NOTARY_PROFILE` | release  | `notarytool` keychain profile. If unset, notarization is skipped.       |
| `BUNDLE_ID`      | no       | Override bundle id (default `dev.claudegrain.menubar`).                 |
| `DEVELOPER_DIR`  | no       | Xcode toolchain (default `/Applications/Xcode.app/Contents/Developer`). |

### Optional dependencies

- [`create-dmg`](https://github.com/create-dmg/create-dmg) — `brew install create-dmg`.
  If absent the script falls back to `hdiutil`.

## CI

`.github/workflows/release.yml` builds and publishes a DMG on every `v*` tag.
The workflow expects these repository secrets:

- `DEVELOPER_ID_CERT_P12_BASE64` — base64-encoded `.p12` of the Developer ID cert.
- `DEVELOPER_ID_CERT_PASSWORD` — password for the `.p12`.
- `NOTARY_API_KEY_ID`, `NOTARY_API_KEY_ISSUER_ID`, `NOTARY_API_KEY_PRIVATE_KEY_BASE64`
  — App Store Connect API key for `notarytool`.

Never commit the certificate, the `.p12`, or the API key.
