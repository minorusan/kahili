# Does Kahili Monitor All Sentry Issues?

**No — Kahili monitors only a subset of your Sentry issues**, filtered by two layers:

---

## Layer 1: Alert Rule Filter (which issues get ingested)

Kahili does **not** poll all Sentry issues. Instead, the kahu poller watches a **single Sentry alert rule** and only ingests issues that trigger that rule.

- **Default alert rule name:** `"Client Errors"`
- **Configurable** via the `alertRuleName` setting in kahu's configuration
- **How it works:** On each poll cycle, kahu calls Sentry's alert rule group-history API to get only the issues that triggered the configured alert rule since the last poll. Issues that don't trigger that alert rule are **never seen** by Kahili.

Additionally, kahu is scoped to a **single Sentry project** (configured via `SENTRY_ORG` and `SENTRY_PROJECT` in `backend/kahu/.env`), so issues from other projects in your Sentry organization are excluded entirely.

## Layer 2: Grouping Rules (which issues get organized into mother issues)

Once issues are ingested, Kahili's **rules engine** further classifies them into "mother issues" (grouped root causes). Only issues that match at least one rule get grouped. The current rules are:

| Rule | What it matches |
|------|----------------|
| NullReferenceException | NRE errors, grouped by stack trace |
| MilestoneError | Milestone-related errors |
| AssetDownload | Asset download failures |
| UnityWebRequest | Unity web request errors |
| SkullIcon | Skull icon errors |
| HttpClientErrorStart | HTTP client error starts |
| SkuIcon | SKU icon errors |
| CouponsService | Coupons service errors |

Issues that don't match any rule are still **stored and visible** in the Issues list — they just won't appear under any Mother Issue.

---

## Summary

| Scope | What's included |
|-------|----------------|
| **Sentry org/project** | Single project only (configured in `.env`) |
| **Issues ingested** | Only those triggering the configured alert rule (default: "Client Errors") |
| **Issues grouped** | Only those matching a classification rule get a Mother Issue |
| **Issues visible** | All ingested issues are visible in the Issues tab, regardless of rules |

To monitor more issues, you can either broaden the conditions on your Sentry alert rule, or change the `alertRuleName` setting to point to a different (broader) alert rule.