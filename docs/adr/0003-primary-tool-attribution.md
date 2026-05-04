# Tool 归因策略:primaryTool

## Status

accepted

## Context

Anthropic API 在 **turn 级别**返 `usage`(input/output/cache_*),不在 tool_use block 级别。同一 assistant turn 可调用多个 tool,但 token 总账只有一份。「per-tool 归因」是 claudegrain 核心差异化,必须给一个明确归因方法。

## Decision

**primaryTool 归因**:取该 assistant turn 的**第一个** `tool_use` block 的 `name` 作 primaryTool,整 turn 的 `usage` 100% 归到它。

`UsageEvent` 同时保留 `tools: [String]`(完整 tool_use 列表)用于审计 / 调试,但 cost / token 聚合只看 `primaryTool`。

UI 上标「按主调用工具归因」一句话说明,避免用户误以为是精确 per-tool 计费。

## Considered Options

- **均分(N tools 各 1/N)**:文档说「估算」。问题:Bash + Edit + Agent 同 turn 时各 1/3,失真严重(实际 Agent 派子 agent 才是大头)。
- **按 `tool_result` 长度加权**:下条 user 消息的 `tool_result` content 长度作权重。问题:实现复杂(要前后看),且 result 长度 ≠ token 消耗(text vs binary 等),仍是估算。
- **turn 级不归因到 tool(砍 per-tool)**:砍掉核心卖点。
- **primaryTool**(选):实现最简,语义清晰(「这个 turn 主要为了调谁」),误差可控 — 抽样统计 75%+ 的 turn 实际只有 1 个 tool_use,误差只在多 tool turn 集中。

## Consequences

- per-tool 排行是「按主调用 tool 归因下的 turn 计数 + token 总和」,不是精确 per-tool 计费。文档里说清。
- 未来若 Anthropic 改 API 给 per-block usage,本归因策略可平滑升级到精确 per-tool,只换 `primaryTool` 计算逻辑,聚合层不动。
- 多 tool 同 turn 是少数(< 25% 抽样),实际产品体感影响小。
