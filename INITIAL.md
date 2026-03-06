# Kahili — System Initialization

## Pre-check

Run: `which kahili`

- If it returns a path → system is already initialized. **Skip this document.**
- If it returns nothing → system needs initialization. Follow all steps below.

---

## Step 1: Collect Required Credentials (Before Installing Anything)

Before running any install commands, ask the user to provide these values:

1. **OpenAI API Key** — from https://platform.openai.com/api-keys
2. **Sentry Auth Token** — from https://sentry.io/settings/auth-tokens/
Required scopes: `event:read`, `event:admin`, `project:read`, `alerts:read`
3. **Sentry Organization slug** — from URL: `sentry.io/organizations/<slug>/`
4. **Sentry Project slug** — from the Sentry project settings
5. **Repository path watched by Sentry** — absolute path to the app repository that sends errors to Sentry (this is **not** the Kahili repository path unless Kahili itself is what Sentry is monitoring)

Do not continue to dependency installation until the user confirms they have these values.

---

## Step 2: Install Dependencies

### Node.js (v20+)
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs
```
Verify: `node -v && npm -v`

### Flutter (stable)
```bash
# Install Flutter SDK to home directory
git clone https://github.com/flutter/flutter.git -b stable ~/.flutter-sdk
```

### System tools
```bash
sudo apt-get install -y git psmisc  # git for repo, psmisc for fuser
```

### Codex CLI (OpenAI agent runtime)
```bash
npm install -g @openai/codex
```

### PATH setup

All tools must be reachable from non-interactive shells (agents spawn commands without login shells). Create symlinks in `/usr/local/bin/`:

```bash
# Flutter — required so codex agent and kahili CLI can find it
sudo ln -sf ~/.flutter-sdk/bin/flutter /usr/local/bin/flutter
sudo ln -sf ~/.flutter-sdk/bin/dart /usr/local/bin/dart

# Verify all required tools are on PATH
which node npm flutter dart codex git fuser
```

If any tool is missing from the output, create a symlink:
```bash
sudo ln -sf $(which <tool>) /usr/local/bin/<tool>
```

Verify: `flutter --version && codex --version`

### Install npm packages
```bash
cd ~/kahili/backend/lib && npm install
cd ~/kahili/backend/kahu && npm install
```

### Install Flutter packages
```bash
cd ~/kahili/client && flutter pub get
```

---

## Step 3: Configure Environment

### Create kahu .env (Sentry worker config)
```bash
cat > ~/kahili/backend/kahu/.env << 'EOF'
SENTRY_TOKEN=
SENTRY_ORG=
SENTRY_PROJECT=
REPO_PATH=
REPORT_UPDATE_INTERVAL=60
EOF
```

### Create kahili .env (parent config)
```bash
cat > ~/kahili/backend/.env << 'EOF'
OPENAI_API_KEY=
EOF
```

### Ask the user to provide:
1. **Sentry Auth Token** — from https://sentry.io/settings/auth-tokens/ (needs `event:read`, `event:admin`, `project:read`, `alerts:read` scopes)
2. **Sentry Organization slug** — from Sentry URL: `sentry.io/organizations/<slug>/`
3. **Sentry Project slug** — from Sentry project settings
4. **Repository path watched by Sentry** — absolute path to the app repo that sends errors to Sentry (not automatically Kahili)
5. **OpenAI API Key** — from https://platform.openai.com/api-keys

Fill the values into the two `.env` files above.

---

## Step 4: Install kahili start/stop Commands

### Create the start script
```bash
sudo tee /usr/local/bin/kahili << 'SCRIPT'
#!/usr/bin/env bash
set -e

KAHILI_DIR="$HOME/kahili"
KAHILI_PORT=3401
KAHU_PORT=3456
LOG_FILE="/tmp/kahili-main.log"

usage() {
  echo "Usage: kahili {start|stop|status|restart}"
  exit 1
}

get_local_ip() {
  hostname -I | awk '{print $1}'
}

do_stop() {
  echo "Stopping kahili..."
  fuser -k "$KAHILI_PORT/tcp" 2>/dev/null || true
  fuser -k "$KAHU_PORT/tcp" 2>/dev/null || true
  sleep 1
  # Double-check
  fuser -k "$KAHILI_PORT/tcp" 2>/dev/null || true
  fuser -k "$KAHU_PORT/tcp" 2>/dev/null || true
  echo "Kahili stopped."
}

do_build() {
  echo "Building backend/lib..."
  (cd "$KAHILI_DIR/backend/lib" && npm run build) || { echo "ERROR: backend/lib build failed"; exit 1; }

  echo "Building backend/kahu..."
  (cd "$KAHILI_DIR/backend/kahu" && npm run build) || { echo "ERROR: backend/kahu build failed"; exit 1; }

  echo "Building Flutter client..."
  (cd "$KAHILI_DIR/client" && flutter build web --no-pub) || { echo "ERROR: Flutter build failed"; exit 1; }
}

do_start() {
  # Kill any existing instances
  fuser -k "$KAHILI_PORT/tcp" 2>/dev/null || true
  fuser -k "$KAHU_PORT/tcp" 2>/dev/null || true
  sleep 2

  # Build everything
  do_build

  # Start in background
  cd "$KAHILI_DIR/backend"
  rm -f kahu.pid
  nohup node lib/dist/index.js > "$LOG_FILE" 2>&1 &
  local PID=$!
  disown "$PID"

  # Wait for server to come up
  echo "Starting kahili (PID $PID)..."
  local TRIES=0
  while [ $TRIES -lt 30 ]; do
    if curl -s "http://localhost:$KAHILI_PORT/api/status" >/dev/null 2>&1; then
      local IP=$(get_local_ip)
      echo ""
      echo "  Kahili is running: http://${IP}:${KAHILI_PORT}"
      echo "  Log: $LOG_FILE"
      echo ""
      return 0
    fi
    sleep 1
    TRIES=$((TRIES + 1))
  done

  echo "WARNING: Kahili did not respond within 30s. Check $LOG_FILE"
  return 1
}

do_status() {
  if curl -s "http://localhost:$KAHILI_PORT/api/status" 2>/dev/null | python3 -m json.tool 2>/dev/null; then
    echo ""
    echo "Kahili is running on port $KAHILI_PORT"
  else
    echo "Kahili is not running."
  fi
}

case "${1:-}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; sleep 1; do_start ;;
  status)  do_status ;;
  *)       usage ;;
esac
SCRIPT

sudo chmod +x /usr/local/bin/kahili
```

### Verify
```bash
kahili status
kahili start
kahili stop
```

---

## Step 5: First Run

```bash
kahili start
```

Open the URL printed by the start command in a browser. Go to Settings tab to verify Sentry connection. The system will begin polling Sentry issues automatically.

---

## Done

The system is now initialized. `kahili start`, `kahili stop`, `kahili restart`, and `kahili status` are available system-wide.
