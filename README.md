# claudegrain

> Granular Claude Code usage in your menu bar — per-repo, per-tool, per-MCP, cache-hit attribution. None of the existing trackers do this.

**English** · [中文](README.zh-CN.md)

<p align="center">
  <img src="docs/screenshots/v18-demo.gif" alt="claudegrain demo — phosphor dark + thermal paper light" width="380">
</p>

## What sets it apart

| Feature | claudegrain | ccseva | ClaudeBar | ClaudeUsageBar | claudecodeusage |
| --- | --- | --- | --- | --- | --- |
| Session block % + reset | ✓ | ✓ | ✓ | ✓ | ✓ |
| Weekly limit | ✓ | partial | ✓ | ✓ | ✓ |
| **Per-repo $ attribution** | ✓ | — | — | — | — |
| **Per-tool token attribution** | ✓ | — | — | — | — |
| **Per-MCP server attribution** | ✓ | — | — | — | — |
| **Cache hit %** | ✓ | — | — | — | — |
| 7-day spend chart | ✓ | — | — | — | — |
| Time-of-day heatmap | ✓ | — | — | — | — |
| Cycle-aware forecast | ✓ | — | — | — | — |
| Per-repo budget alerts | ✓ | — | — | — | — |
| Native Swift / SwiftUI | ✓ | Electron | ✓ | ✓ | ✓ |

## Data sources (3-tier fallback)

1. **OAuth Path** — Reads Claude Code OAuth token from macOS Keychain, calls the undocumented `api.anthropic.com/api/oauth/usage` endpoint. Zero configuration, real values for session + weekly limits.
2. **JSONL Path** — Parses `~/.claude/projects/**/*.jsonl` directly. Powers all the per-repo / per-tool / per-MCP / cache-hit attribution (the OAuth API doesn't expose any of this). Also serves as fallback for rate limits via P90 estimation.
3. **CLI Path** — Final fallback: shells out to `claude /usage` and scrapes stdout. Used only when both above fail.

See [docs/adr/0001-three-tier-data-source.md](docs/adr/0001-three-tier-data-source.md).

## Install

```bash
brew tap FlyTOmeLight/claudegrain
brew install --cask claudegrain
```

Or grab the latest DMG manually from [GitHub Releases](https://github.com/FlyTOmeLight/claudegrain/releases/latest).

> **First launch — Gatekeeper hoop**
>
> Current builds are **ad-hoc signed** (no paid Apple Developer ID yet). macOS will refuse to open the app on first launch.
>
> 1. Drag **claudegrain.app** into `/Applications/`
> 2. Right-click the app → **Open** → confirm
> 3. Subsequent launches open normally
>
> Or via Terminal:
> ```sh
> xattr -dr com.apple.quarantine /Applications/claudegrain.app
> open /Applications/claudegrain.app
> ```

Requires macOS 14+ (Sonoma). Apple Silicon and Intel both supported.

### Build from source

```bash
git clone https://github.com/FlyTOmeLight/claudegrain
cd claudegrain
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash scripts/build-dmg.sh
open dist/claudegrain.app
```

Bundle id is `dev.claudegrain.menubar`. See [`scripts/README.md`](scripts/README.md).

## Privacy

- All credentials stay on your machine. No telemetry. No analytics.
- The OAuth token is read from your Keychain, only sent to `api.anthropic.com`.
- JSONL parsing is local-only.
- Source is fully open under MIT — verify yourself.

## License

MIT — see [LICENSE](LICENSE).
