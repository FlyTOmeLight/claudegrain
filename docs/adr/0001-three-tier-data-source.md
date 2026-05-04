# 三层降级数据源:OAuth → JSONL → CLI

## Status

accepted

## Context

Anthropic 没公开稳定的「Claude Code 5h / weekly 剩余配额」API。现有竞品采取四种互不兼容的策略,各有缺陷。

## Decision

主路径 **OAuth Path**:从 macOS Keychain 读 Claude Code OAuth token,撞未公开端点 `api.anthropic.com/api/oauth/usage`。零配置(已登录 CC 即工作),返回 5h + weekly 真值。

降级 **JSONL Path**:解析 `~/.claude/projects/**/*.jsonl`,P90 推算配额上限。同时承担**详细归因**(per-repo / per-tool / per-MCP / cache hit) — OAuth API 不暴露这些。

最终 **CLI Path**:`claude /usage` shell out 抓 stdout。仅作 OAuth + JSONL 双双失败时的「死也能看个数」兜底。

## Considered Options

- **claude.ai 浏览器 cookie**(ClaudeUsageBar 路径):需用户手动复制 cookie,易过期;**砍**
- **纯 P90 ML 推算**(Maciek-roboblog 路径):无认证零配置,但永远是估算非真值;**降级用,不主用**
- **`ccusage` CLI 包装**(ccseva 路径):多一个 Node 进程,且未做 rate limit;**JSONL Path 内自解析,不依赖 ccusage**

## Consequences

- **OAuth endpoint 是未公开的** — Anthropic 可改可关。降级链(JSONL → CLI)就是为这个风险准备的。endpoint 一变,app 不死,只是退到估算 + 详细归因仍工作。
- **OAuth 路径不给详细归因**(per-repo/tool/MCP/cache),所以 JSONL 永远跑,不是单纯 fallback。两者并行,职责互补。
- **三路径并存增加测试成本** — 每条都要 mock + 集成测;但这是差异化护城河,值得。
