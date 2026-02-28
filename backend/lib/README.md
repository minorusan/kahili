# Kahili — Process Manager & Backend

Kahili is the main backend orchestrator for the kahili system. It manages kahu as a subprocess, provides a configuration API, and spawns Claude Code agents to investigate Sentry errors.

## Quick Start

```bash
cd backend/lib
npm install
npm run dev    # build + start
```

Kahili starts on port **3400** (configurable via `KAHILI_PORT`).

## What It Does

On startup, kahili:

1. Increments the shared build number in `backend/build.json`
2. Checks if kahu is already running via `backend/kahu.pid`
   - If running and up-to-date: leaves it alone
   - If running but stale (lower build): kills it
   - If dead or missing: cleans up
3. Builds kahu (`npm run build` in `backend/kahu/`)
4. Spawns kahu as a child process, piping its output with `[kahu]` prefix
5. Starts the HTTP + WebSocket server

## API Endpoints

### Status

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | System status (build, kahu PID, uptime) |
| `GET` | `/api/status` | Same as above |

Response:
```json
{
  "name": "kahili",
  "build": 8,
  "kahuPid": 5678,
  "kahuBuild": 8,
  "uptime": 120
}
```

### Kahu Settings

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/kahu-settings` | Read current kahu `.env` settings |
| `POST` | `/api/kahu-settings` | Apply new settings, restart kahu |

POST body — any subset of keys (merged with existing):
```json
{
  "SENTRY_TOKEN": "sntryu_...",
  "SENTRY_ORG": "my-org",
  "SENTRY_PROJECT": "my-project",
  "POLL_INTERVAL": "60",
  "ALERT_RULE_NAME": "Client Errors",
  "WEB_PORT": "3456",
  "REPO_PATH": "/path/to/game/repo"
}
```

When `REPO_PATH` is set, it backfills the path into all existing mother issue JSON files. Kahu is then rebuilt and restarted with the new env.

### Investigations

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/investigate` | Current investigation status + report |
| `POST` | `/api/investigate` | Start a new investigation |
| `DELETE` | `/api/investigate` | Cancel running investigation |

POST body:
```json
{
  "motherIssueId": "48d164c0f6422ead",
  "branch": "release/3.30.15",
  "additionalPrompt": "Focus on the popup lifecycle"
}
```

Only `motherIssueId` is required. `branch` and `additionalPrompt` are optional.

Only one investigation can run at a time — returns `409` if one is already active.

The spawned Claude agent:
- Runs at the configured `REPO_PATH` with `--dangerously-skip-permissions`
- Uses only read-only git commands (`git show`, `git log`, `git grep`, `git blame`)
- Writes progress to `backend/docs/investigations/<motherIssueId>.md`
- Produces a structured report with root cause, suggested fix, risk assessment, and assignee

### WebSocket

Connect to `ws://localhost:3400` to receive real-time investigation updates:

```json
{ "type": "investigation:started",   "data": { "motherIssueId", "pid", "status" } }
{ "type": "investigation:progress",  "data": { "motherIssueId", "status", "report" } }
{ "type": "investigation:completed", "data": { "motherIssueId", "status", "report" } }
```

Progress is broadcast every ~1 second as the agent writes to the report file.

## Build Number System

`backend/build.json` is a shared build counter:
```json
{ "build": 8, "updatedAt": "2026-02-28T..." }
```

- Incremented by kahili on every startup
- Read by kahu to display in its banner
- Used to detect stale kahu processes: if kahu's recorded build < current build, it gets rebuilt

`backend/kahu.pid` tracks the running kahu process:
```json
{ "pid": 5678, "build": 8 }
```

## Project Structure

```
backend/lib/
  src/
    index.ts          Entry point — banner, build, ensureKahu, startServer
    build.ts          Read/increment backend/build.json
    kahu-manager.ts   PID tracking, process lifecycle, build & spawn kahu
    server.ts         HTTP endpoints + WebSocket attachment
    settings.ts       Read/write kahu .env, backfill mother issues
    investigator.ts   Spawn claude agent, watch report, broadcast progress
    websocket.ts      WS server attached to HTTP, broadcast helper
  dist/               Compiled JS output
  package.json
  tsconfig.json
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KAHILI_PORT` | `3400` | HTTP + WebSocket server port |

## Scripts

| Script | Description |
|--------|-------------|
| `npm run build` | Compile TypeScript |
| `npm start` | Run compiled server |
| `npm run dev` | Build + start |
