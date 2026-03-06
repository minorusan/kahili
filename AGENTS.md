# Kahili — Agent Reference

**FIRST:** Check if `kahili start` and `kahili stop` commands exist on this system (run `which kahili`). If they do NOT exist, read `INITIAL.md` and follow it to initialize the system before doing anything else.

---

You are working inside the Kahili repository. This document contains everything you need to implement features, fix bugs, and make changes.

## What is Kahili

Sentry issue tracker with Flutter web client and Node.js/TypeScript backend, running on Raspberry Pi 5 (Debian, ARM64). It polls Sentry for issues, groups them into "mother issues" by configurable rules, and provides investigation, archiving, reporting, and AI-powered Q&A.

## Architecture

Two-process Node.js system + Flutter web frontend:

| Component | Port | Language | Source | Build |
|-----------|------|----------|--------|-------|
| **kahili** (parent) | 3401 | TypeScript (ESM) | `backend/lib/src/` | `cd backend/lib && npm run build` |
| **kahu** (worker) | 3456 | TypeScript (ESM) | `backend/kahu/src/` | `cd backend/kahu && npm run build` |
| **Flutter web** | served by kahili | Dart | `client/lib/` | `cd client && flutter build web --no-pub` |

- kahili spawns kahu as child process, proxies its API under `/api/kahu/*`
- kahili serves the Flutter web build from `client/build/web/`
- Both TypeScript packages use `"type": "module"` — all local imports need `.js` extension
- No test framework is configured — verify changes by building successfully

## Directory Layout

```
backend/
  lib/                    # kahili parent
    src/                  # TypeScript source
      index.ts            # entry point — loads dotenv, starts server
      server.ts           # HTTP server, all API routes, static file serving
      agent-spawn.ts      # spawnAgent() — runs codex CLI for all AI agents
      investigator.ts     # investigation agent (analyzes Sentry errors)
      rule-generator.ts   # rule generation agent (creates grouping rules)
      help-agent.ts       # FAQ agent (answers questions about Kahili)
      develop-agent.ts    # develop agent (implements feature requests)
      kahu-manager.ts     # spawns/manages kahu child process
      settings.ts         # reads/writes kahu .env settings
      websocket.ts        # WebSocket server for real-time broadcasts
      build.ts            # build counter (build.json)
      logger.ts           # logging utility
    dist/                 # compiled JS output
    package.json          # deps: dotenv, ws
  kahu/                   # kahu Sentry worker
    src/
      index.ts            # entry point
      server.ts           # HTTP server (issues, mother-issues, rules, archive)
      sentry-client.ts    # Sentry API client (read + write)
      poller.ts           # polls Sentry alert rule for new issues
      reporter.ts         # generates daily markdown reports
      storage.ts          # file-based storage for issues and state
      types.ts            # SavedIssue, SentryEvent, etc.
      rules/              # grouping rules
        rule.ts           # Rule abstract class + MotherIssue interface
        index.ts          # loads and applies all rules
        storage.ts        # persists mother issues as JSON
        *.ts              # individual rule implementations
    data/                 # runtime data (gitignored)
      issues/             # cached Sentry issues as JSON
      mother-issues/      # generated mother issue JSON files
      reports/            # daily markdown reports
      state.json          # poller state (last poll time, etc.)
    .env                  # SENTRY_TOKEN, SENTRY_ORG, SENTRY_PROJECT, etc.
    dist/
    package.json          # deps: dotenv
  data/                   # kahili parent data (gitignored)
    help-questions/       # FAQ: {id}.json + {id}.md per question
    develop-requests/     # Develop: {id}.json + {id}.md per request
  docs/
    investigations/       # investigation reports: {motherIssueId}.md
  build.json              # {"build": N} — auto-incremented on start
  kahu.pid                # PID file for kahu process
  .env                    # OPENAI_API_KEY (loaded by dotenv in kahili)
client/
  lib/
    main.dart             # app entry point
    api/
      api_client.dart     # static HTTP client — all API calls
    models/
      api_models.dart     # DTOs for investigation, help, develop, rules, etc.
      mother_issue.dart   # MotherIssue model
      sentry_issue.dart   # SentryIssue model
    screens/
      home_screen.dart    # main scaffold with bottom nav (Sentry, Incoming, Reports, Settings, Help)
      help_tab.dart       # Help tab — TabBar with FAQ and Develop subtabs
      faq_subtab.dart     # FAQ questions list
      develop_subtab.dart # Develop requests list
      help_ask_page.dart  # ask FAQ question + watch agent
      help_detail_page.dart  # view FAQ answer
      develop_ask_page.dart  # submit feature request + watch agent
      develop_detail_page.dart # view feature implementation report
      sentry_tab.dart     # mother issues list
      mother_issue_detail.dart # mother issue detail (investigation, archive, etc.)
      incoming_tab.dart   # unresolved issues triage
      reports_tab.dart    # daily reports list
      settings_tab.dart   # settings form
      archive_dialog.dart # bulk archive Sentry issues
      investigate_dialog.dart # start investigation dialog
      widgets/            # reusable widgets
        investigation_panel.dart
        child_issues_section.dart
        stack_trace_block.dart
        issue_card.dart
        investigating_badge.dart
        shared_widgets.dart
    theme/
      kahili_theme.dart   # KahiliColors + KahiliTheme.dark
  build/web/              # compiled output (gitignored)
  pubspec.yaml            # deps: http, flutter_markdown, url_launcher, shared_preferences
```

## Build Commands

```bash
# Backend — kahili parent
cd backend/lib && npm run build

# Backend — kahu worker
cd backend/kahu && npm run build

# Flutter web client
cd client && flutter build web --no-pub
```

All three must succeed for a valid deployment. Always build what you changed.

## After Making Changes

After implementing and building successfully:

1. **Commit** your changes: `git add <files> && git commit -m "feat: description"`
2. Do NOT push to remote
3. Do NOT run `kahili restart` or `kahili stop` — the system restarts automatically after your commit

## API Routes (kahili — port 3401)

### Management
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/status` | Server status (build, uptime, kahu PID) |
| GET/POST | `/api/kahu-settings` | Read/write kahu .env settings |
| POST | `/api/client-log` | Receive client-side error logs |

### Investigation Agent
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/investigate` | Current investigation status |
| POST | `/api/investigate` | Start investigation (body: {motherIssueId, branch?, additionalPrompt?}) |
| DELETE | `/api/investigate` | Cancel investigation |
| GET | `/api/reports/status` | List investigated mother issue IDs |
| GET | `/api/report/:id` | Get investigation report markdown |

### Rule Generation Agent
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/generate-rule` | Current generation status |
| POST | `/api/generate-rule` | Start generation (body: {prompt}) |
| DELETE | `/api/generate-rule` | Cancel generation |
| POST | `/api/regenerate-rule` | Delete old rule + generate new (body: {ruleName, prompt}) |

### FAQ Agent
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/help-agent` | Current FAQ agent status |
| POST | `/api/help-agent` | Start FAQ agent (body: {question}) |
| DELETE | `/api/help-agent` | Cancel FAQ agent |
| GET | `/api/help-questions` | List all FAQ questions |
| GET | `/api/help-questions/:id` | Get question + answer detail |

### Develop Agent
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/develop-agent` | Current develop agent status |
| POST | `/api/develop-agent` | Start develop agent (body: {request}) |
| DELETE | `/api/develop-agent` | Cancel develop agent |
| GET | `/api/develop-requests` | List all develop requests |
| GET | `/api/develop-requests/:id` | Get request + report detail |

### Kahu Proxy (forwarded to port 3456)
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/kahu/mother-issues` | List all mother issues |
| GET | `/api/kahu/mother-issues/:id` | Get single mother issue |
| GET | `/api/kahu/issues` | List all raw Sentry issues |
| GET | `/api/kahu/rules` | List grouping rules |
| POST | `/api/kahu/archive-issues` | Bulk archive Sentry issues |

### Other
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/repo-info` | Git branches and tags |
| GET | `/api/daily-reports` | List daily report dates |
| GET | `/api/daily-reports/:date` | Get daily report |

## Code Patterns & Conventions

### TypeScript (backend)
- ESM modules — all local imports use `.js` extension: `import { foo } from "./bar.js"`
- No frameworks — raw `node:http` server, manual route matching
- JSON responses via `json(res, data, status)` helper
- Request body parsing via `readBody(req)` → `JSON.parse()`
- File-based storage — JSON metadata + markdown content files
- Agent spawning: all agents use `spawnAgent(prompt, cwd)` from `agent-spawn.ts`
- WebSocket broadcasts via `broadcast(event, data)` from `websocket.ts`
- Logging via `log.info()`, `log.error()`, `log.warn()` from `logger.ts`

### Dart/Flutter (client)
- Material 3 dark theme — use `KahiliColors` constants, never hardcode colors
- `ApiClient` has all API methods as static futures
- Models in `api_models.dart` with `fromJson` factory constructors
- Screens are `StatefulWidget` with `_load()` pattern for data fetching
- Agent status polling: `Timer.periodic(Duration(seconds: N), callback)`
- Cards: `Container` with `BoxDecoration(color: KahiliColors.surfaceLight, borderRadius: 12, border: KahiliColors.border)`
- Markdown rendering: `flutter_markdown` package with custom `MarkdownStyleSheet`
- Navigation: `Navigator.push(MaterialPageRoute(...))`
- No state management library — plain `setState()`

### Theme Colors (use these, don't invent new ones)
| Name | Hex | Use |
|------|-----|-----|
| `bg` | #0C0C14 | Page background |
| `surface` | #151520 | App bar, nav bar |
| `surfaceLight` | #1C1C2E | Cards, containers |
| `surfaceBright` | #242438 | Elevated surfaces |
| `flame` | #FF6D00 | Primary accent, buttons, headings |
| `cyan` | #00E5FF | Secondary accent, links, code |
| `gold` | #FFD600 | Running/progress states |
| `emerald` | #43A047 | Success/completed states |
| `error` | #FF3D00 | Error states |
| `textPrimary` | #E8E8F0 | Main text |
| `textSecondary` | #9E9EB8 | Labels, descriptions |
| `textTertiary` | #5C5C78 | Hints, timestamps |
| `border` | #2A2A40 | Card borders, dividers |

## Mother Issue Structure

```typescript
interface MotherIssue {
  id: string;              // sha256(groupingKey).slice(0,16)
  groupingKey: string;
  ruleName: string;
  title: string;
  errorType: string;
  level: string;           // "error" | "warning" | "info" | "fatal"
  metrics: { totalOccurrences, affectedUsers, firstSeen, lastSeen };
  childIssueIds: string[];
  sentryLinks: string[];
  smartlookUrls: string[];
  stackTrace?: { frames: Array<{filename, function, lineno, inApp}> };
  childStatuses: string[]; // parallel to childIssueIds
  allChildrenArchived: boolean;
  createdAt: string;
  updatedAt: string;
}
```

## Grouping Rules

Rules live in `backend/kahu/src/rules/`. Each rule extends `Rule`:

```typescript
abstract class Rule {
  abstract readonly name: string;
  abstract readonly description: string;
  abstract readonly logic: string;          // human-readable explanation
  abstract groupingKey(issue: SavedIssue): string | null;  // null = doesn't match
}
```

Rules are loaded in `rules/index.ts` and applied to all issues. A grouping key maps issues to mother issues.

## Git

- The repo root is at the parent of `backend/` and `client/`
- `.gitignore` covers: `node_modules/`, `dist/`, `.env`, `build/`, `data/`, `logs/`, `kahu.pid`, `build.json`
- Commit with descriptive messages: `git commit -m "feat: add X"` or `git commit -m "fix: resolve Y"`
- Never push — the system handles deployment

## Environment

- **Platform:** Raspberry Pi 5, 16GB RAM, Debian, ARM64
- **Node.js:** available globally
- **Flutter:** available globally
- **TypeScript:** installed per-package as devDependency
- **No test runners** — validate by building
- **Repo path:** `~/kahili` (absolute: `/home/erkamen/kahili`)
