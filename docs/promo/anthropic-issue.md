# Issue draft for `anthropics/claude-code`

Goal: surface the per-repo / per-tool attribution gap that motivated claudegrain
to the Claude Code team. Doubles as backlink — visitors clicking the
referenced repo find an actual implementation.

**File against**: https://github.com/anthropics/claude-code/issues

---

**Title**:
> Feature request: per-repo / per-tool attribution in `claude /usage`

**Body**:

`claude /usage` and the `api/oauth/usage` endpoint expose session and weekly
totals, but not the breakdown that's most actionable for engineers managing
their own quota:

- **Per-repo $**: which `cwd` is consuming the budget?
- **Per-tool tokens**: are tool calls (Bash, Read, Edit, …) or model thinking
  the dominant cost?
- **Per-MCP server**: which connected MCP is most expensive?
- **Cache hit rate**: how much of the input is being served from the
  prompt-cache vs. paid input?

All four are derivable today from the JSONL transcripts under
`~/.claude/projects/**/*.jsonl` — I built [claudegrain]
(https://github.com/FlyTOmeLight/claudegrain), an open-source menu-bar app, to
do this attribution offline. Two issues with the JSONL-only approach that a
first-party API would solve:

1. The JSONL parser has to handle schema drift (e.g. the v1 → v2 dedup-key
   migration when older events lacked `message.id` / `requestId`). A stable
   API contract would absorb that.
2. The OAuth path's session + weekly numbers don't agree with my
   JSONL-derived totals to the cent — there's an unaccounted-for source of
   truth on Anthropic's side, presumably more granular than what gets emitted
   into the local transcripts.

Even a read-only extension to `oauth/usage` returning a `[{ cwd, tokens,
cost_usd }]` array would unblock a lot of self-hosted dashboards.

(Repo for context — happy to reformat anything that's useful upstream:
https://github.com/FlyTOmeLight/claudegrain · ADR-0001 documents the three-tier
data-source compromise; ADR-0003 covers the per-tool attribution heuristic.)

---

## Don't

- Don't open this until v1.0.x has been stable for a week — Anthropic eng
  will click and judge the repo's polish.
- Don't post if the issue tracker has a similar request open already; comment
  on theirs instead.
- Don't be antagonistic. Frame as "here's a gap and a workaround" not "your
  API is incomplete."
