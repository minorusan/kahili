# Sentry Tab vs. Incoming Tab

These two tabs show different views of the issues Kahili tracks from Sentry.

## Sentry Tab — Grouped "Mother Issues"

The **Sentry** tab displays **mother issues** — these are groups of related Sentry errors that share a common root cause. Each mother issue:

- Is created by a **rule** (e.g. NRE rule, Coupons Service rule) that automatically groups matching child issues together
- Shows **aggregated metrics** across all child issues: total occurrences, affected users, and child count
- Has a **rule name badge** (e.g. "NRE", "coupons-service") indicating which grouping rule matched
- Can be **investigated** by the AI agent, which analyzes the error and suggests fixes
- Can be **archived** (appears dimmed at the bottom of the list)
- Supports **filtering and sorting** by affected users or last seen time

## Incoming Tab — Ungrouped "Orphan" Issues

The **Incoming** tab displays **orphan issues** — individual Sentry issues that have **not been matched by any rule** and therefore don't belong to any mother issue. These are issues that:

- Were polled from Sentry but no grouping rule matched them
- Show a **"NO RULE"** badge instead of a rule name
- Display their **individual** occurrence count and user count (not aggregated)
- Need **triage** — you can view them and decide whether to create a new rule to group them

## How They Relate

```
Sentry API
   │
   ▼
All polled issues
   │
   ├── Matched by a rule ──► grouped into Mother Issue ──► Sentry tab
   │
   └── No rule matched ──► orphan ──► Incoming tab
```

When the Incoming tab shows **"All issues are grouped"**, it means every issue from Sentry has been matched by at least one rule and assigned to a mother issue. If new issues appear in Incoming, it typically means you need a new rule to handle that error pattern.

## Summary

| | Sentry Tab | Incoming Tab |
|---|---|---|
| **Shows** | Mother issues (grouped) | Orphan issues (ungrouped) |
| **Rule status** | Matched by a rule | No rule matched |
| **Metrics** | Aggregated across children | Individual issue stats |
| **Action needed** | Investigate root cause | Create a rule to group them |
| **Goal** | Analyze & fix grouped errors | Triage & classify new errors |
