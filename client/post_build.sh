#!/bin/bash
# Post-build cleanup: remove service worker, manifest, and add cache-busting
# Run after: flutter build web

BUILD_DIR="$(dirname "$0")/build/web"
STAMP=$(date +%s)

# Remove service worker file
rm -f "$BUILD_DIR/flutter_service_worker.js"

# Remove manifest (prevents PWA installation/caching)
rm -f "$BUILD_DIR/manifest.json"

# Strip serviceWorkerSettings AND add cache-busting timestamp to main.dart.js URL
python3 -c "
import re, sys
path = '$BUILD_DIR/flutter_bootstrap.js'
with open(path, 'r') as f:
    content = f.read()
# Strip service worker settings
content = re.sub(
    r'_flutter\.loader\.load\(\{[^}]*serviceWorkerSettings[^)]*\}\)',
    '_flutter.loader.load({})',
    content,
    flags=re.DOTALL
)
# Cache-bust main.dart.js — change the URL so browser can't use stale cache
content = content.replace('\"main.dart.js\"', '\"main.dart.js?v=$STAMP\"')
with open(path, 'w') as f:
    f.write(content)
"

echo "Post-build cleanup done: removed SW, manifest, stripped SW registration, cache-bust v=$STAMP"
