# Kahili System Architecture

Kahili is a **Sentry issue tracker** with a Flutter web client and Node.js/TypeScript backend, designed to run on a Raspberry Pi 5.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter Web (Dart), compiled to JS/HTML/WASM |
| **Backend (parent)** | Node.js + TypeScript (`kahili`, port 3401) |
| **Backend (worker)** | Node.js + TypeScript (`kahu`, port 3456) |
| **AI Agents** | Claude Code CLI (spawned as child processes) |
| **Real-time** | WebSockets (`ws` library) |
| **Data Storage** | JSON files on disk (no database) |
| **External APIs** | Sentry API, OpenAI (for rules) |
| **Hardware** | Raspberry Pi 5 |

---

## Two-Process Architecture

Kahili runs as **two cooperating Node.js processes**:

### 1. Kahili (Parent Process Manager) — Port 3401

**Source:** `backend/lib/src/` (11 TypeScript modules)

The parent process is the main entry point. It:

- **Serves the Flutter web app** — static file server with cache-busting, preloader HTML, and SPA routing
- **Manages kahu's lifecycle** — builds, spawns, monitors, and restarts the worker process via PID file tracking (`kahu.pid` stores `{ pid, build }`)
- **Proxies API calls** — routes `/api/kahu/*` requests to kahu on port 3456
- **Runs AI agents** — spawns Claude Code CLI processes for investigations, rule generation, and help Q&A
- **WebSocket server** — broadcasts real-time updates (investigation progress, etc.) to connected clients
- **Settings management** — reads/writes kahu's `.env` configuration

**Key modules:**
- `server.ts` — HTTP server, API routing, static file serving
- `kahu-manager.ts` — process lifecycle (build, spawn, kill, health check)
- `investigator.ts` — AI-powered error investigation agent
- `rule-generator.ts` — AI-powered grouping rule generation
- `help-agent.ts` — AI-powered Q&A about Kahili itself
- `agent-spawn.ts` — spawns Claude CLI with PTY allocation via `script -qc`
- `websocket.ts` — WebSocket broadcast for real-time UI updates
- `settings.ts` — manages kahu `.env` configuration

### 2. Kahu (Sentry Worker) — Port 3456

**Source:** `backend/kahu/src/` (8 TypeScript modules + rules/)

The worker process handles all Sentry interaction:

- **Polls Sentry** — queries alert rule group-history on a configurable interval to discover new/updated issues
- **Stores issues** — saves issue data + events as JSON files in `data/issues/`
- **Runs classification rules** — groups raw Sentry issues into "mother issues" using configurable rules
- **Generates daily reports** — periodic reports of resolved/archived issues with Jira links and comments
- **Serves its own API** — JSON API for issues, mother issues, rules, and reports (accessed via kahili's proxy)

**Key modules:**
- `sentry-client.ts` — Sentry API client (issues, events, activities, alert rules)
- `poller.ts` — polling loop with configurable interval, fetches new issues + refreshes statuses
- `storage.ts` — file-based persistence for issues and state
- `rules/index.ts` — rule engine that groups child issues into mother issues
- `rules/*.ts` — individual grouping rules (NRE, asset download, HTTP errors, etc.)
- `reporter.ts` — daily report generator (checks per-issue activity feeds)
- `server.ts` — HTTP server with HTML + JSON API endpoints

---

## Process Lifecycle

```
Startup:
  kahili starts → increments build counter → ensureKahu(build)
    → checks PID file → if stale/dead: npm run build → spawn node
    → health check (polls localhost:3456/api/issues, 10s timeout)
    → starts HTTP server on port 3401

Shutdown (SIGINT/SIGTERM):
  kahili → kills all AI agents (SIGTERM → 2s → SIGKILL)
         → kills kahu (SIGTERM → 2s → SIGKILL)
         → cleans up port occupants via fuser
```

---

## Flutter Web Client

**Source:** `client/lib/` (Dart)

A single-page web app compiled to JS and served by kahili. Key screens:

| Tab | File | Purpose |
|-----|------|---------|
| **Sentry** | `sentry_tab.dart` | Mother issues list with filtering |
| **Incoming** | `incoming_tab.dart` | Unresolved child issues needing triage |
| **Reports** | `reports_tab.dart` | Daily report viewer |
| **Help** | `help_tab.dart` | AI Q&A about Kahili |
| **Settings** | `settings_tab.dart` | Configuration UI |

Detail screens: `mother_issue_detail.dart` (with investigate button), `report_detail.dart`, `investigate_dialog.dart` (real-time investigation progress)

**Dependencies:** `http` (API calls), `flutter_markdown` (report rendering), `url_launcher`, `shared_preferences`

---

## Data Flow

```
Sentry API
    ↓ (poll every N seconds)
  Kahu (poller)
    ↓ (save to disk)
  data/issues/*.json          ← raw Sentry issues + events
    ↓ (classification rules)
  data/mother-issues/*.json   ← grouped "mother issues"
    ↓ (daily reporter)
  data/reports/YYYY-MM-DD.md  ← daily summaries
    ↓ (API)
  Kahili HTTP server ←→ Flutter web client
    ↓ (on demand)
  Claude AI agents → docs/investigations/*.md
```

---

## AI Agent System

Kahili spawns **Claude Code CLI** as child processes for three capabilities:

1. **Investigation** — analyzes a mother issue, reads the source repo via `git show`, and writes a structured report with root cause, risk assessment, and suggested fix
2. **Rule Generation** — creates new TypeScript grouping rules from natural language descriptions
3. **Help Agent** — answers questions about Kahili itself by reading the source code

Agents are spawned via `script -qc` for PTY allocation, tracked in a set for cleanup, and their output is piped through the logger. Progress is broadcast to the Flutter client via WebSocket.

---

## Storage Model

All data is stored as **flat JSON files** on disk (no database):

```
backend/kahu/data/
  state.json              ← poller state (last poll time, processed issues)
  issues/<id>.json        ← individual Sentry issues with events
  mother-issues/<id>.json ← grouped mother issues
  reports/YYYY-MM-DD.md   ← daily reports
backend/data/
  help-questions/<id>.json/md ← help Q&A history
backend/docs/
  investigations/<id>.md  ← investigation reports
```
