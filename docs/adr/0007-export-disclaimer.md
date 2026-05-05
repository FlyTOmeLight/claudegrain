# Export disclaimer in CSV/JSON output

## Status

accepted

## Context

B2 ships CSV/JSON export so users can take their usage data to
spreadsheets, accountants, internal cost dashboards. The data is:

1. Cost-attributed via the **primaryTool** strategy (ADR-0003): a
   turn's tokens get billed to its first `tool_use` block, not split
   per tool.
2. Cost-priced via a **public LiteLLM-derived price catalog**, not the
   user's actual Anthropic invoice. Discounted enterprise rates,
   credits, and beta pricing are not reflected.

Either of these is enough to make a reimbursement-claim spreadsheet
mismatch the Anthropic billing portal. We've already had test reports
where users paste claudegrain numbers into expense reports and finance
flags the discrepancy.

## Decision

Every export, regardless of dimension or format, MUST carry a
machine-readable disclaimer:

- **CSV**: three `# `-prefixed comment lines as the first lines of the
  file. SQL importers and spreadsheets either skip these (`#` comment
  conventions in `psql`/Excel-import wizards) or expose them as the
  first row of values where the user can see them.
- **JSON**: a top-level `_meta` object containing `attribution`,
  `disclaimer`, `generated_at`, `range`, and `dimension` fields.

The disclaimer text is fixed:

```
claudegrain export — primaryTool attribution, public price-table cost estimate.
Not the Anthropic billing source of truth.
```

## Considered options

- **Show the disclaimer only in the UI sheet** — gets stripped when
  data leaves claudegrain. Defeats the purpose.
- **Watermark each row** — too noisy, breaks pivot tables.
- **Skip the disclaimer for raw events** — raw events are the most
  compelling reimbursement evidence and the most likely to mismatch.
  All dimensions need it.

## Consequences

- A spreadsheet user opening the CSV will see the comment lines as the
  first row of values (Excel, Numbers). That's intentional —
  prominence > strict CSV cleanliness.
- JSON consumers parse `_meta` first; if a tool ignores it, they at
  least had it.
- Future CSV consumers need to know to skip the leading `#` lines. We
  don't add a "skip-line count" field — the convention is broadly
  understood and adding metadata about the metadata is over-engineering.
- The CSV header text and JSON `_meta.disclaimer` text are slightly
  different in current code (CSV: 2-line declaration; JSON: single
  sentence). A follow-up could DRY them into a `EXPORT_DISCLAIMER`
  constant; both convey the same intent so this is cosmetic.
