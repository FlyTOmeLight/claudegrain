# Show HN drafts

## Variant A — feature-led (recommended)

**Title** (max 80 chars):
> Show HN: Claudegrain – Per-repo, per-tool Claude Code usage in your menu bar

**URL**: https://github.com/FlyTOmeLight/claudegrain

**First comment** (post immediately after the submission so it pins to top):

> Author here. Built this because the existing Claude Code usage trackers (ccseva,
> ClaudeBar, ClaudeUsageBar) only surface session % and weekly limits — no
> attribution. I wanted to know which repo / tool / MCP server was actually
> burning my Max20 quota.
>
> Three data sources, fallback in this order:
> 1. OAuth Path: undocumented `api.anthropic.com/api/oauth/usage` endpoint, real
>    session + weekly values, zero config (token from Keychain).
> 2. JSONL Path: parses `~/.claude/projects/**/*.jsonl` directly. The OAuth API
>    doesn't expose per-repo / per-tool / per-MCP attribution, so this is the
>    only way to get it. Also drives a P90 estimator for rate limits.
> 3. CLI Path: shells out to `claude /usage` as a last-resort fallback.
>
> Tech: native Swift / SwiftUI, GRDB-only deps, ~10MB binary, runs as
> LSUIElement (no Dock icon). Phosphor receipt aesthetic — works in dark and
> light.
>
> Couple of things I'd love feedback on:
>
> - The per-tool attribution model (ADR-0015 in the repo) splits a turn's
>   tokens across the tool_use blocks proportionally. It's a heuristic, not
>   precise per-tool billing — open to better algorithms.
> - The OAuth endpoint is undocumented; if Anthropic ships a real one I'll
>   migrate. The state machine in `Auth/DataSourceCoordinator` is exactly the
>   contingency for that breaking.
>
> MIT-licensed. Builds (ad-hoc signed DMGs) on the GitHub Releases page;
> Homebrew cask submission pending.

## Variant B — story-led (alternate)

**Title**:
> Show HN: I shipped a $172 Claude Code day before realizing one repo did 80% of it

**First comment**:
> Yesterday I noticed my Max20 quota burning faster than usual. Anthropic's
> built-in `/usage` shows session percent and a weekly bar — that's it. No
> way to ask "which of my repos is doing the spending."
>
> So I built claudegrain ...

(then same body as Variant A)

---

## Pre-submission checklist

- [ ] README has a 30s demo gif near the top
- [ ] Homebrew cask submitted (or noted as "in review")
- [ ] CI green on the latest tag
- [ ] At least one v1.x release on the Releases page (HN reviewers click Releases)
- [ ] You're free to babysit the post for 4-6 hours after submitting (replies = ranking)

## Timing

Submit Tue–Thu 06:30–08:30 PT. Avoid Mon (Show HN flood) and Fri (low traffic).

## Antipatterns

- Don't submit and disappear — every reply in the first hour boosts.
- Don't shill in comments. Be technically frank, including limitations.
- Don't ask for stars in the post. HN allergic.
