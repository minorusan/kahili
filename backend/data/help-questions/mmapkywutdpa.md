# Watching for a Specific Release in Kahili

Kahili tracks release information from Sentry, but doesn't currently have a dedicated "watch a release" feature. Here's what's available and how to best use it:

---

## What Kahili Already Tracks

Every issue pulled from Sentry includes the `release` field from its events. Kahili extracts this and stores it as **`firstSeenRelease`** — the release version where the issue first appeared. This propagates up to **mother issues** as the earliest release across all grouped child issues.

You can see this in:
- **Mother issue detail page** — shown as "First Seen Release" in the metadata table and as "First version" in the timeline
- **Individual issue events** — each event shows its release version
- **Daily reports** — resolved issues show if they were fixed "in release X.Y.Z" or "in next release"

---

## Best Approach: Use the Filter System

The most practical way to watch for a specific release right now is the **Filter & Sort** feature on the Sentry tab:

1. Open the **Sentry** tab
2. Tap the **filter icon** (top-right, next to the search bar)
3. Under **Filter Strings**, add your release version string (e.g. `1.2.0` or `2024.03`)
4. Issues whose serialized data matches that string will be **highlighted** with a flame icon and **sorted to the top** of the list

**How it works:** The filter serializes each mother issue's fields (title, error type, grouping key, stack traces, Sentry links, etc.) into a single string and checks if your filter text appears anywhere in it. Release version strings often appear in Sentry permalink URLs and issue metadata, so this can catch release-related issues.

**Limitation:** The filter currently checks title, error type, rule name, grouping key, stack traces, and Sentry links — but does **not** include `firstSeenRelease` in the serialized search blob. So this works best if the release string appears in issue titles or Sentry URLs.

---

## View Release Info Per Issue

To check which release an issue appeared in:

1. Open any **mother issue** from the Sentry tab
2. Look at the **metadata table** for "First Seen Release"
3. Or scroll to the **timeline** section where it appears as "First version" in cyan

For individual events, click through to the issue detail where each event shows its release version.

---

## What's Not Currently Supported

- **Release-specific polling** — the Sentry poller uses alert rules and time ranges, not release filters
- **Release-based grouping rules** — the 8 grouping rules match on error type, stack traces, and titles, not releases
- **Release alerts/thresholds** — no way to set "alert if release X has > N errors"
- **Release dropdown/selector** — no UI to pick a release and see only its issues

---

## Summary

| Method | Works? | Best For |
|--------|--------|----------|
| **Filter strings** with release version | Partial | Catching issues mentioning the release in titles/URLs |
| **Mother issue detail** page | Yes | Checking which release a known issue appeared in |
| **Daily reports** | Yes | Seeing what was resolved in which release |
| **Dedicated release watch** | Not yet | Would need a new feature |

For now, your best bet is combining the **filter string** with the release version and regularly checking **mother issue details** for the `firstSeenRelease` field.
