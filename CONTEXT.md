# claudegrain

> repo 目录仍叫 `menu-hub`(历史名),产品 / bundle / 命名空间统一 **claudegrain**。

macOS 菜单栏 app,实时显示 Claude Code 真实使用统计。差异化卖点:**per-repo / per-tool / per-MCP / cache-hit** 细粒度("grain")归因 — 现有竞品(ccseva、ClaudeBar、ClaudeUsageBar、claudecodeusage)都没做。

## Language

**Session Block**:
Claude Code 5 小时滚动配额窗;首次活动起算,5h 后重置。
_Avoid_: Session(歧义,jsonl 也叫 session),5h Window

**Weekly Limit**:
每周配额上限,Pro/Max5/Max20 各异;周一 UTC 零点重置。
_Avoid_: Weekly Quota,Week Cap

**Plan**:
Anthropic 订阅档位 — Pro / Max5 / Max20 / Custom(P90 推算)。
_Avoid_: Tier,Subscription

**Repo Attribution**:
按 jsonl 的 `cwd` 字段把 token 成本归到具体项目。
_Avoid_: Project Tracking(歧义,project 也指 ~/.claude/projects 的 hash dir)

**Tool Attribution**:
按 assistant turn 的 `content[].name` 把 token 成本归到具体工具(Bash/Edit/Agent/MCP/...)。
_Avoid_: Tool Cost

**MCP Attribution**:
Tool Attribution 子集;按 `mcp__<server>__<tool>` 前缀解析归到具体 MCP server。
_Avoid_: MCP Cost

**Cache Hit Rate**:
`cache_read_input_tokens / (cache_read + cache_creation + input_tokens)`;反映 prompt cache 利用效率。
_Avoid_: Cache Ratio,Cache Efficiency

**OAuth Path**:
主数据源 — 从 macOS Keychain 读 Claude Code OAuth token,撞未公开端点 `api.anthropic.com/api/oauth/usage`。来源:richhickson/claudecodeusage。
_Avoid_: API Path

**JSONL Path**:
降级数据源 — 解析 `~/.claude/projects/<repo-hash>/*.jsonl`,P90 推算配额上限。
_Avoid_: Local Path,File Path

**CLI Path**:
最后兜底 — shell out `claude /usage` 抓 stdout。
_Avoid_: Shell Path

## Relationships

- **OAuth Path** → **Session Block** + **Weekly Limit** 真值;不给详细归因
- **JSONL Path** → **Repo / Tool / MCP / Cache Hit** 全维度归因;**Session Block** 只能 P90 估
- **CLI Path** → **Session Block** 真值,无归因
- 主路径:OAuth(rate limit)+ JSONL(详细归因)双源互补
- 降级链:OAuth 失败 → JSONL P90 → CLI stdout

## Example dialogue

> **用户:** 「我今天 $3 花哪去了?」
> **menu-hub:** Repo:`new/prism-endpoint` $1.80,`tools/menu-hub` $0.90,其他 $0.30。Tool:`mcp__exa__search` 占 41%,Bash 22%,Edit 18%。Cache hit 87%,省了 ~$4.20。
> **用户:** 「5h 还剩多少?」
> **menu-hub:** OAuth 路径返回真值 32% 剩,3h12min 后 reset。

## Flagged ambiguities

- 「session」既指 Claude Code 单次 jsonl 会话(`sessionId`),又指 Anthropic rate limit 的 5h 窗口 → 后者改称 **Session Block**,前者保留 **Session**。
- 「project」既指用户 git repo,又指 `~/.claude/projects/<hash>` 的 jsonl 容器 → 用户视角统一称 **Repo**(基于 `cwd`),内部存储路径才叫 project dir。
