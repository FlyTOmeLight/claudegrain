# claudegrain

Granular Claude Code usage in your menu bar. Per-repo, per-tool, per-MCP, cache-hit attribution — none of the existing trackers do this.

| Phosphor (dark) | Thermal paper (light) |
| --- | --- |
| ![dark](docs/screenshots/v18-dark.png) | ![light](docs/screenshots/v18-light.png) |

## What sets it apart

| Feature | claudegrain | ccseva | ClaudeBar | ClaudeUsageBar | claudecodeusage |
| --- | --- | --- | --- | --- | --- |
| Session block % + reset | ✓ | ✓ | ✓ | ✓ | ✓ |
| Weekly limit | ✓ | partial | ✓ | ✓ | ✓ |
| **Per-repo $ attribution** | ✓ | — | — | — | — |
| **Per-tool token attribution** | ✓ | — | — | — | — |
| **Per-MCP server attribution** | ✓ | — | — | — | — |
| **Cache hit %** | ✓ | — | — | — | — |
| Native Swift / SwiftUI | ✓ | Electron | ✓ | ✓ | ✓ |

## Data sources (3-tier fallback)

1. **OAuth Path** — Reads Claude Code OAuth token from macOS Keychain, calls
   the undocumented `api.anthropic.com/api/oauth/usage` endpoint. Zero
   configuration, real values for session + weekly limits.
2. **JSONL Path** — Parses `~/.claude/projects/**/*.jsonl` directly. Powers all
   the per-repo / per-tool / per-MCP / cache-hit attribution (the OAuth API
   doesn't expose any of this). Also serves as fallback for rate limits via
   P90 estimation.
3. **CLI Path** — Final fallback: shells out to `claude /usage` and scrapes
   stdout. Used only when both above fail.

See [docs/adr/0001-three-tier-data-source.md](docs/adr/0001-three-tier-data-source.md).

## Install

(v0.1 work in progress — DMG + Homebrew Cask coming.)

```bash
git clone https://github.com/<your>/claudegrain
cd claudegrain
swift build -c release
.build/release/claudegrain
```

Requires macOS 14+ (Sonoma). Apple Silicon and Intel both supported.

The signed `.app` ships with bundle id `dev.claudegrain.menubar` (override via
`BUNDLE_ID=...` when invoking `scripts/build-dmg.sh`). See
[`scripts/README.md`](scripts/README.md) for the full release pipeline.

## Privacy

- All credentials stay on your machine. No telemetry. No analytics.
- The OAuth token is read from your Keychain, only sent to
  `api.anthropic.com`.
- JSONL parsing is local-only.
- Source is fully open under MIT — verify yourself.

## License

MIT — see [LICENSE](LICENSE).
