# How Issues Are Created and Grouped in Kahili

## Overview

Kahili uses a two-stage pipeline: **poll Sentry for raw issues**, then **group them into "mother issues"** using a rule-based system. Each mother issue represents a shared root cause across one or more Sentry child issues.

---

## Stage 1: Issue Creation (Polling Sentry)

The **kahu worker** (`backend/kahu/src/poller.ts`) runs a continuous poll cycle:

1. **Queries Sentry** for alert rule group-history over a time window (last poll time → now)
2. **Fetches up to 5 recent events** for each new or updated issue
3. **Saves each issue** to `backend/kahu/data/issues/<issueId>.json` as a `SavedIssue`:
   - Full Sentry issue metadata (title, status, count, userCount, level, etc.)
   - Up to 5 most recent full events (with stack traces, tags, contexts)
   - `firstSeenRelease` (backfilled from the oldest event's release)
   - Timestamps (`savedAt`, `updatedAt`)
4. **Refreshes statuses** — re-checks all tracked issues for status changes (resolved, ignored, unresolved)
5. **Triggers rule processing** after each poll cycle

---

## Stage 2: Grouping into Mother Issues

After polling, `processRules()` in `backend/kahu/src/rules/index.ts` runs:

### How Rules Work

Each rule implements a `groupingKey(issue)` function that returns either:
- A **string key** if the issue matches the rule — issues with the **same key become one mother issue**
- `null` if the issue doesn't match

### The 8 Active Rules

| Rule | Matches | Grouping Strategy |
|------|---------|-------------------|
| **NRE Rule** | NullReferenceException errors | Groups by stack trace hash — same call stack = same mother issue |
| **LiveopId Rule** | Titles containing MongoDB ObjectIDs | Normalizes IDs to placeholders, groups by normalized title |
| **Milestone Error** | Titles starting with `[Milestone Error]` | All go into a single bucket |
| **Asset Download** | Download/asset-related keywords | Groups by extracted asset name |
| **Unity WebRequest** | UnityWebRequest exceptions | All go into a single bucket |
| **Skull Icon** | "cannot get skull icon" in message | Single bucket |
| **HTTP Client Error in Start** | HTTPClientError in "start" function | Single bucket |
| **SKU Icon** | "Can not get SKU icon" in title | Groups by extracted SKU value |

### Aggregation Process

For each unique grouping key, a **MotherIssue** is created with:

- **Unique ID**: `sha256(groupingKey)` truncated to 16 hex chars
- **Aggregated metrics**:
  - `totalOccurrences` = sum of all child issue counts
  - `affectedUsers` = sum of all child user counts
  - `firstSeen` / `lastSeen` = earliest and latest timestamps across children
  - `level` = highest severity (fatal > error > warning > info > debug)
- **Child references**: list of all Sentry issue IDs in the group
- **Stack trace**: extracted from the first child's first event
- **Status tracking**: `allChildrenArchived` flag — true when every child is resolved/ignored

### Persistence

Mother issues are saved to `backend/kahu/data/mother-issues/<id>.json`. On each cycle:
- Existing mother issues have their `createdAt` timestamp preserved
- Metrics are fully recalculated from current child data
- New children are added automatically if they match the same grouping key

---

## Example Flow

```
Sentry Alert fires for issue #12345 (NullReferenceException)
  ↓
Poller fetches issue + 5 events, saves to data/issues/12345.json
  ↓
Rules processing runs:
  NRE Rule matches → groupingKey = "NullReferenceException::stacktrace::a3f8b2c1..."
  ↓
Mother issue with ID sha256("NullReferenceException::stacktrace::a3f8b2c1...")[0:16]
  already exists with child #11111?
  → YES: add #12345 to childIssueIds, re-aggregate metrics
  → NO:  create new mother issue with #12345 as first child
  ↓
Save to data/mother-issues/<id>.json
  ↓
Available via API: GET /api/issues
```

---

## Key Design Decisions

- **Deterministic IDs**: Mother issue IDs are derived from the grouping key hash, so the same logical group always gets the same ID across restarts
- **Rule-based, not AI-based**: Grouping uses deterministic pattern-matching rules, making it predictable and fast
- **One issue, multiple rules**: An issue can technically match multiple rules, creating separate mother issues for different grouping perspectives
- **Automatic re-aggregation**: Metrics update every poll cycle as new child issues appear or statuses change