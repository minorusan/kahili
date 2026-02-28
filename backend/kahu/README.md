# Kahu — Sentry Worker

Kahu is a Sentry error monitoring worker. It polls Sentry for triggered alerts, stores issue data locally, groups related errors into "mother issues" via a rules engine, and serves a web UI for browsing everything.

## Quick Start

```bash
cd backend/kahu
cp .env.example .env   # fill in your Sentry credentials
npm install
npm run dev             # build + start
```

Kahu starts on port **3456** (configurable via `WEB_PORT`).

In production, kahu is managed by kahili — you don't run it directly. Kahili builds, spawns, and restarts kahu automatically.

## Environment Variables

Configure via `.env` in the kahu directory:

| Variable | Default | Description |
|----------|---------|-------------|
| `SENTRY_TOKEN` | *required* | Sentry API auth token |
| `SENTRY_ORG` | *required* | Sentry organization slug |
| `SENTRY_PROJECT` | *required* | Sentry project slug |
| `POLL_INTERVAL` | `300` | Seconds between Sentry API polls |
| `ALERT_RULE_NAME` | `Client Errors` | Name of the Sentry alert rule to monitor |
| `WEB_PORT` | `3456` | HTTP server port |
| `REPO_PATH` | — | Local path to source repo (set via kahili) |

These can be managed remotely via kahili's `POST /api/kahu-settings` endpoint.

## How It Works

### Polling Cycle

1. Finds the configured alert rule by name
2. Queries Sentry for issues triggered in the last poll interval
3. For each new/updated issue:
   - Fetches full event details (stack traces, breadcrumbs, contexts)
   - Saves to `data/issues/{issueId}.json`
4. Runs the rules engine to update mother issues
5. Sleeps for `POLL_INTERVAL` seconds, then repeats

### Rules Engine

Rules group individual Sentry issues into **mother issues** — deduplicated error groups.

Each rule implements:
- `groupingKey(issue)` — returns a deterministic key if the issue matches, or `null` to skip

Issues with the same grouping key are merged into a single mother issue with aggregated metrics.

#### Built-in Rules

**NullReferenceException Rule** (`nre-rule.ts`)
- Detects NRE via exception type, metadata, or title
- Groups by SHA256 hash of the full stack trace
- Key format: `NullReferenceException::stacktrace::{hash}`

#### Mother Issue Structure

```json
{
  "id": "48d164c0f6422ead",
  "groupingKey": "NullReferenceException::stacktrace::abc123",
  "ruleName": "NullReferenceException",
  "title": "NullReferenceException: Object reference...",
  "errorType": "Error",
  "level": "error",
  "metrics": {
    "totalOccurrences": 1499,
    "affectedUsers": 1478,
    "firstSeen": "2025-12-12T...",
    "lastSeen": "2026-02-28T..."
  },
  "childIssueIds": ["7105676343"],
  "repoPath": "/path/to/repo",
  "stackTrace": { "frames": [...] },
  "createdAt": "...",
  "updatedAt": "..."
}
```

Mother issue IDs are stable — `sha256(groupingKey).slice(0, 16)`.

#### Adding a New Rule

1. Create `src/rules/my-rule.ts` extending `Rule`
2. Implement `name`, `description`, and `groupingKey(issue)`
3. Register it in `src/rules/index.ts` by adding to the `rules` array

## Web UI

Kahu serves a dark-themed web UI:

| Route | Description |
|-------|-------------|
| `/` | Issues list — sortable table with level, event count, users, last seen |
| `/issue/:id` | Issue detail — tags, events with stack traces, breadcrumbs, contexts |
| `/mother-issues` | Mother issues list — grouped errors with aggregate metrics |
| `/mother-issue/:id` | Mother issue detail — stack trace, child issues |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/issues` | All issues (summary: id, title, level, count, lastSeen) |
| `GET` | `/api/issues/:id` | Full issue with events |
| `GET` | `/api/mother-issues` | All mother issues sorted by lastSeen |
| `GET` | `/api/mother-issues/:id` | Single mother issue |

All API responses are JSON. Issues are sorted most-recent-first.

## Data Storage

All data is file-based, stored under `data/` (gitignored):

```
data/
  state.json                 Poll state (last poll time, processed issues)
  issues/
    {issueId}.json           Full issue data + events
  mother-issues/
    {motherIssueId}.json     Grouped/deduplicated issues
```

Logs are written to `logs/` with timestamped filenames.

## Build Number

When managed by kahili, kahu reads `backend/build.json` at startup and displays the build number in its ASCII banner. This is informational — kahu works fine standalone without it (displays `?`).

## Project Structure

```
backend/kahu/
  src/
    index.ts              Entry point — config, banner, init
    logger.ts             File + console logger
    server.ts             HTTP server with web UI and JSON API
    poller.ts             Sentry API polling loop
    sentry-client.ts      Sentry REST API client with rate limiting
    storage.ts            Issue persistence (JSON files)
    types.ts              TypeScript interfaces for Sentry data
    rules/
      index.ts            Rule runner — groups issues, computes aggregates
      rule.ts             MotherIssue interface + Rule abstract class
      nre-rule.ts         NullReferenceException grouping rule
      storage.ts          Mother issue persistence
  dist/                   Compiled JS output
  data/                   Runtime data (gitignored)
  logs/                   Log files
  .env                    Environment config (gitignored)
  package.json
  tsconfig.json
```

## Scripts

| Script | Description |
|--------|-------------|
| `npm run build` | Compile TypeScript |
| `npm start` | Run compiled server |
| `npm run dev` | Build + start |
