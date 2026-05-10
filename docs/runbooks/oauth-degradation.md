# Runbook — diagnosing OAuth path degradation

When the popover header reads `JSONL (于 HH:MM)` instead of `OAUTH ✓`,
the `DataSourceCoordinator` has fallen off the OAuth path and is
serving last-good-snapshot or JSONL-only estimates. This runbook
shows how to figure out *why*.

## Symptom anatomy

- `OAUTH ✓` — `state == .oauthLive`, last fetch succeeded.
- `JSONL (于 HH:MM)` — `state ∈ {jsonlOnly, oauthAuthError, oauthDeprecated}`.
  The `HH:MM` is the timestamp of the last successful OAuth fetch
  (`AppModel.lastOAuthSyncAt`). If you see this an hour after launch,
  OAuth has been broken for that hour.
- Brief stale popover (1-2 minutes) — `state == .oauthBackoff`. Recovers
  on its own after the server-suggested wait. Not a problem unless it
  keeps recurring.

## Per-state diagnosis

### `.oauthAuthError`

Token failed 401/403 or the keychain read itself raised. Most common cause:

- The Claude Code CLI re-issued tokens (e.g. after `claude /login`) and
  the old one is dead. Re-auth in the CLI then `Refresh` (F5) in the
  popover.
- macOS Keychain ACL was edited externally and now refuses claudegrain.

To confirm, watch the live OSLog stream:

```bash
log stream --process claudegrain \
           --predicate 'subsystem == "dev.claudegrain.menubar" AND category == "oauth"' \
           --style compact
```

You should see `OAuth tick: keychain read failed: ...` or
`OAuth HTTP 401: ...` lines.

### `.oauthDeprecated`

The endpoint returned 404 or HTML. The undocumented `oauth/usage` path
has either moved or been retired. Action: open an issue, the app keeps
working from JSONL.

### `.oauthBackoff` lingering > 5 min

The server keeps returning 429 with a long `Retry-After`. v1.0.5+ honors
the header value verbatim; if you saw `Retry-After: 1800` in the logs,
you'll be in backoff for 30 minutes. Action: nothing — that's the
contract.

If the header is absent, the coordinator falls back to a 60 second wait.
Pre-v1.0.5 used a 60s wait *unconditionally*, which produced retry storms
when Anthropic actually wanted 30 minutes. If you're on a pre-v1.0.5
build, upgrade.

### `.jsonlOnly` despite a valid token in CLI

`KeychainTokenError.notLoggedIn` was raised. Probable causes:

- Sandbox / TCC denial — claudegrain has no access to the credential
  keychain item the CLI writes. Gatekeeper "Open" dance was skipped.
- The CLI uses a different keychain ACL than the one the app was
  signed for.

Confirm: `log stream` will show `keychain has no token; degrading to JSONL`.

## Forcing a transition

Settings has no manual OAuth retry — the path is fully managed. To force
a tick, click `Refresh` (F5) in the popover or restart the app. If you
need to wipe the path entirely, sign out via `claude /logout` then back
in.

## When to file an issue

- `.oauthDeprecated` for >24h (endpoint genuinely retired).
- `.oauthAuthError` immediately after `claude /login` succeeded.
- `.oauthBackoff` for >1h with no `Retry-After` header (server bug).
- Repeated `.oauthBackoff` cycles within minutes (we may need server-aware
  exponential backoff on top of `Retry-After`).

Attach the OSLog dump:

```bash
log show --process claudegrain --last 1h \
         --predicate 'subsystem == "dev.claudegrain.menubar" AND category == "oauth"' \
         --style compact > oauth-trace.txt
```
