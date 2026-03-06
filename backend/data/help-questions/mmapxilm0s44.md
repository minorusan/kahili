# Kahili Security Assessment

## Can Kahili Perform Invasive Operations?

### Sentry: Read & Write
Kahili **can** modify Sentry issues. The `SentryClient` has both read and write capabilities:
- **Read:** `getIssues()`, `searchIssues()`, `getIssueEvents()`, `getIssueActivities()`, `getAlertRules()`
- **Write:** `archiveIssue()` — archives (ignores) issues via PUT, `addIssueComment()` — posts comments via POST

The **archive feature** allows bulk archiving of multiple Sentry issues at once from the Mother Issue detail page. This is an intentional invasive operation that changes issue status in Sentry.

### Archive Risk: Poor Grouping Rules
The biggest operational risk is **archiving issues that shouldn't be archived** due to an inaccurate grouping rule. Mother issues group child Sentry issues by rules (NRE patterns, milestone matches, etc.). If a rule is too broad, it may group unrelated issues together. Bulk archiving all children of such a mother issue would archive issues that are still relevant.

**Mitigations:**
- A confirmation dialog shows the grouping rule before bulk archive, so developers can review it
- Archive results are per-issue — partial failures are reported
- Archived issues can be unarchived in Sentry
- The "Until escalating" archive mode auto-reopens if the issue resurfaces

### Repository: Read-Only
The investigation agent is explicitly restricted to read-only git commands:
- Allowed: `git show`, `git log`, `git grep`, `git blame`
- Blocked: `git checkout`, `git pull`, `git commit`, or any file modifications

The agent runs via `execFile()` with array arguments (safe from shell injection).

### Jira: No Integration
There is **no Jira integration** in Kahili.

---

## Is the System Safe?

Kahili is designed as a **monitoring dashboard with limited write capabilities** and is generally safe in its intended environment (a trusted local network on a Pi 5). However, there are security considerations:

### What's Done Well
- **Path traversal protection** — static file serving validates resolved paths
- **Safe process spawning** — uses `execFile()` with array args, not shell interpolation
- **HTML escaping** — output is properly escaped to prevent XSS
- **Body size limits** — HTTP request bodies capped at 1MB
- **Archive confirmation** — warning dialog with rule review before bulk operations

### Known Weaknesses (Not Breaches)

| Severity | Issue | Impact |
|----------|-------|--------|
| **High** | No authentication on any endpoint | Anyone on the network can access all data |
| **High** | Settings API exposes Sentry token in plaintext | `GET /api/kahu-settings` returns the token |
| **High** | Settings can be changed without auth | `POST /api/kahu-settings` can overwrite tokens |
| **High** | Archive endpoint has no auth | Anyone on the network can archive Sentry issues |
| **Medium** | No CORS headers | Potentially vulnerable to cross-site request forgery |
| **Medium** | No rate limiting | Could be spammed with investigation/rule/archive requests |
| **Low** | Secrets stored in plaintext `.env` | Standard practice but risky on shared systems |

### Known Breaches
There are **no known breaches** — these are design limitations, not exploited vulnerabilities. Kahili assumes it runs on a trusted local network where all users are authorized.

---

## Summary

| System | Can Kahili Modify It? | Details |
|--------|----------------------|---------|
| **Sentry** | **Yes** | Can archive issues and add comments |
| **Repository** | No | Read-only git commands enforced |
| **Jira** | No | No integration exists |
| **Local filesystem** | Limited | Writes only to its own `data/` directory (reports, issues, state) |

**Bottom line:** Kahili is primarily a monitoring tool but now has write capabilities for Sentry issue archiving. The main risks are (1) lack of authentication — if exposed beyond your local network, anyone could archive issues or change settings, and (2) bulk archiving issues grouped by an inaccurate rule. Always review the grouping rule before bulk archiving. For a home/office Pi deployment, this is acceptable. For broader exposure, authentication should be added.
