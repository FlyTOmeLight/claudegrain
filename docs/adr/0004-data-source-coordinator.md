# DataSourceCoordinator 状态机 + JSONL always-on

## Status

accepted

## Context

ADR-0001 描述 OAuth → JSONL → CLI 三层降级,但只是散文。实现时需要明确:

- 各种 OAuth 失败模式(401/403/429/5xx/timeout/HTML body/schema mismatch)分别如何反应?
- 抖动避免:OAuth 短暂 429 不应让 UI 在「真值 ↔ P90 估算」之间反复跳。
- JSONL 不只是「OAuth 失败时的 fallback」 — 它**永远跑**,因为详细归因(per-repo/tool/MCP/cache)只有 jsonl 给。

## Decision

- **JSONL Path 永远在线**(always-on),负责所有详细归因。不因 OAuth 状态影响。
- **OAuth Path 由 `DataSourceCoordinator` actor 显式管理状态机**:

| Event | Current | Next | Action |
|-------|---------|------|--------|
| boot | — | `oauthChecking` | 读 Keychain |
| keychain hit | `oauthChecking` | `oauthLive` | start polling /oauth/usage |
| keychain miss | `oauthChecking` | `jsonlOnly` | rate limit 走 P90 |
| 200 OK | `oauthLive` | `oauthLive` | publish snapshot |
| 401/403 | `oauthLive` | `oauthAuthError` | refresh token; on fail → `jsonlOnly` |
| 429 | `oauthLive` | `oauthBackoff(retry_after)` | hold UI on last good snapshot |
| 5xx | `oauthLive` | `oauthLive` | exp backoff retry 3x; on fail → `jsonlOnly` |
| schema mismatch | `oauthLive` | `oauthDeprecated` | permanent → `jsonlOnly` + log |
| user toggle off | * | `jsonlOnly` | settings opt-out |

- **CLI Path** 仅在 `jsonlOnly` 且 jsonl 也读不到(权限 / 沙箱)时启用,作为「showing nothing 的避免」。
- **抖动避免**:`oauthBackoff` 不切回 `jsonlOnly`,UI 仍显示 OAuth 上次值,只是停止轮询直到 retry-after 过。

## Consequences

- 状态机在代码中显式,不再散落在 if-else。便于测试(每条 transition 一个测试)。
- UI 永远有数据(JSONL 持续),OAuth 是「真值升级」而非「主路径」。
- 用户设置里可强制 `jsonlOnly` 模式(隐私顾虑 / 不想撞未公开 endpoint)。
