# Kahili

Sentry issue tracker with Flutter web client and Node.js backend running on Pi 5.

## Architecture

Two-process system:

- **kahili** (parent process manager) — port 3401, serves Flutter web app + management API
- **kahu** (Sentry worker) — port 3456, polls Sentry, generates reports, serves issue data API

kahili spawns kahu as a child process and manages its lifecycle. On exit (SIGINT/SIGTERM), kahili kills all child agents and kahu with SIGTERM → SIGKILL escalation (2s timeout).

## Directory layout

```
backend/
  lib/              # kahili parent — TypeScript
    src/            # source
    dist/           # compiled output
    package.json    # build: tsc, start: node dist/index.js
  kahu/             # kahu worker — TypeScript
    src/            # source
    dist/           # compiled output
    data/           # runtime data (reports, mother-issues, state)
    .env            # kahu config (SENTRY_TOKEN, SENTRY_ORG, etc.)
    package.json    # build: tsc, start: node dist/index.js
  build.json        # build counter (auto-incremented on start)
  kahu.pid          # PID file for kahu process (auto-managed)
client/
  lib/              # Flutter web app source
  build/web/        # compiled Flutter output (served by kahili)
```

## Starting the stack

```bash
# 1. Build both TypeScript packages
cd ~/kahili/backend/lib && npm run build
cd ~/kahili/backend/kahu && npm run build

# 2. Build Flutter web client
cd ~/kahili/client && flutter build web --no-pub

# 3. Start kahili (it will build + spawn kahu automatically)
cd ~/kahili/backend && rm -f kahu.pid && node lib/dist/index.js > /tmp/kahili-main.log 2>&1 &
```

kahili on start:
1. Increments build counter in `build.json`
2. Calls `ensureKahu(build)` — checks PID file, rebuilds + spawns kahu if stale or dead
3. Waits for kahu health check (polls `localhost:3456/api/issues`, 10s timeout)
4. Starts HTTP server on port 3401
5. Registers SIGINT/SIGTERM cleanup handlers

## Restarting after code changes

**IMPORTANT:** Always kill ports with `fuser` before restarting. A stale process holding the port will cause `EADDRINUSE` crash on the new one, and the old (stale) process keeps serving old code silently.

### Changed kahu code only (`backend/kahu/src/`):
```bash
cd ~/kahili/backend/kahu && npm run build
fuser -k 3401/tcp 2>/dev/null; fuser -k 3456/tcp 2>/dev/null; sleep 2
cd ~/kahili/backend && rm -f kahu.pid && node lib/dist/index.js > /tmp/kahili-main.log 2>&1 &
```

### Changed kahili parent code (`backend/lib/src/`):
```bash
cd ~/kahili/backend/lib && npm run build
fuser -k 3401/tcp 2>/dev/null; fuser -k 3456/tcp 2>/dev/null; sleep 2
cd ~/kahili/backend && rm -f kahu.pid && node lib/dist/index.js > /tmp/kahili-main.log 2>&1 &
```

### Changed Flutter client (`client/lib/`):
```bash
cd ~/kahili/client && flutter build web --no-pub
# Restart kahili so it serves the fresh build
fuser -k 3401/tcp 2>/dev/null; fuser -k 3456/tcp 2>/dev/null; sleep 2
cd ~/kahili/backend && rm -f kahu.pid && node lib/dist/index.js > /tmp/kahili-main.log 2>&1 &
```

### Any change — full restart:
```bash
cd ~/kahili/backend/lib && npm run build
cd ~/kahili/backend/kahu && npm run build
cd ~/kahili/client && flutter build web --no-pub
fuser -k 3401/tcp 2>/dev/null; fuser -k 3456/tcp 2>/dev/null; sleep 2
cd ~/kahili/backend && rm -f kahu.pid && node lib/dist/index.js > /tmp/kahili-main.log 2>&1 &
```

**Do NOT suggest users visit `/clear` or hard-refresh to fix caching issues.** If the browser shows stale content, it means the server process is stale — restart kahili properly using the steps above.

## Process lifecycle details

- `kahu.pid` stores `{ pid, build }` — kahili uses this to detect stale processes
- `ensureKahu()` skips rebuild if PID is alive AND build number matches
- `restartKahu()` always kills + rebuilds + respawns (used by settings API)
- Port cleanup: `fuser -k <port>/tcp` runs before spawning to kill orphans
- Kill order: SIGTERM first, wait 3s, then SIGKILL if still alive
- `lib/prestart` script kills ports 3401+3456 before start (for `npm start`)

## Logs

- kahili main log: `/tmp/kahili-main.log`
- kahu per-session log: `backend/kahu/logs/<timestamp>.log`
- All kahu stdout is piped through kahili with `[kahu]` prefix

## Ports

| Service | Port | Purpose |
|---------|------|---------|
| kahili  | 3401 | Web UI + management API |
| kahu    | 3456 | Sentry worker API (internal, proxied via `/api/kahu/*`) |
