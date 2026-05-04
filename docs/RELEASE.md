# Release Playbook

Two paths. Pick whichever matches the project's stage.

| Path | Cost | Gatekeeper UX | Use when |
| --- | --- | --- | --- |
| **A · ad-hoc** (current) | $0 | First launch needs right-click → Open | Early days, open-source crowd, GitHub Releases |
| **B · Developer ID + notarize** | $99/y | Double-click opens silently | Mass distribution, brew cask, less-technical users |

## Path A — ad-hoc release (free)

This is what the repo ships today.

### One-time

Nothing.

### Cut a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

That's it. `.github/workflows/release.yml` runs `scripts/build-dmg.sh` (which
falls back to ad-hoc signing when `DEVELOPER_ID` is unset), uploads the DMG,
and publishes a GitHub Release with first-launch instructions in the body.

### Verify locally before tagging

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash scripts/build-dmg.sh
hdiutil verify dist/claudegrain-0.1.0.dmg
open dist/claudegrain.app    # Right-click → Open the first time
```

### Caveats

- Users see a Gatekeeper warning on first launch. README covers the
  workaround.
- Homebrew Cask review tends to reject ad-hoc-signed casks. Stay self-hosted
  on GitHub Releases until upgrading to path B.

## Path B — notarized release ($99/y Apple Developer Program)

### Prereqs

- Apple Developer Program account (paid, $99/y)
- Developer ID Application certificate enrolled in your local Keychain
- App Store Connect API key (issuer ID + key ID + .p8 private key)

### One-time local setup

```bash
xcrun notarytool store-credentials "claudegrain-notary" \
  --apple-id "you@example.com" \
  --team-id "ABCDEFGHIJ" \
  --password "app-specific-password"
```

### One-time GitHub repo secrets

Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of your Developer ID `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | password protecting that `.p12` |
| `NOTARY_API_KEY_ID` | App Store Connect key ID |
| `NOTARY_API_KEY_ISSUER_ID` | issuer UUID |
| `NOTARY_API_KEY_PRIVATE_KEY_BASE64` | base64 of the `.p8` private key |

Encode helpers:
```bash
base64 -i Certificates.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXX.p8 | pbcopy
```

### Switch the workflow to path B

Restore the certificate import + notarytool steps in
`.github/workflows/release.yml`. Reference: the git history before path A
was the live notarized version. Pseudo-diff:

```yaml
# add steps before "Build DMG":
- name: Import Developer ID certificate
  env: { CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }} ... }
  run: |
    # security create-keychain / import / set-key-partition-list
    # echo "DEVELOPER_ID=$IDENTITY" >> $GITHUB_ENV

- name: Stage notary API key
  env: { NOTARY_KEY_BASE64: ${{ secrets.NOTARY_API_KEY_PRIVATE_KEY_BASE64 }} ... }
  run: |
    # base64 --decode > notary_key.p8
    # xcrun notarytool store-credentials claudegrain-notary --key ...
    # echo "NOTARY_PROFILE=claudegrain-notary" >> $GITHUB_ENV
```

### Verify the notarized DMG

```bash
spctl -a -t exec -vv dist/claudegrain.app   # expect: source=Notarized Developer ID
xcrun stapler validate dist/claudegrain.app  # expect: 100% valid
```

### Cut a release (same as path A)

```bash
git tag v0.2.0
git push origin v0.2.0
```

## Rollback

If a release ships broken:

```bash
gh release delete v0.1.0 --cleanup-tag
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
```

Fix, bump VERSION, re-tag.
