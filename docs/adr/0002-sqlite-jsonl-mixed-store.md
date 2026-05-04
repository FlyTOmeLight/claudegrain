# SQLite cache + JSONL source-of-truth 混合存储

## Status

accepted

## Context

历史趋势(7-day 折线、跨日 repo 累计、weekly 推算)需要历史数据。jsonl 永远在 `~/.claude/projects/`,但每次冷启重扫几 GB 太慢。纯内存方案则跨进程会话失忆。

## Decision

- **JSONL = source of truth**:`~/.claude/projects/**/*.jsonl` 永远是唯一权威。SQLite 可随时整库 rebuild,无独立持久数据。
- **SQLite = 物化视图**:`~/Library/Application Support/menu-hub/cache.db`,索引 `(timestamp, repo, tool, mcp_server, model)` 便于聚合查询。
- **冷启 / 时间窗外** → 查 SQLite。
- **实时增量** → FSEvents 触发,只解析新 jsonl 行,append 到 SQLite + 内存热缓存。
- **保留期 90 天**,旧分区批量 vacuum。

## Consequences

- jsonl 文件被用户删 / 移动 / Anthropic 改 schema → SQLite 仍可服务历史查询,但实时增量会失败,要 fallback 到「最后一次成功 rebuild」并通知用户。
- SQLite schema 变 → migration 不必兼容旧 db,直接整库 rebuild(因为 jsonl 还在)。降低 migration 心智负担。
- 90 天保留期是设计取舍:足够覆盖 weekly 趋势 + 月度回顾,且 db < ~50 MB(假设重度用户)。
