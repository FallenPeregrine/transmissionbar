#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Run this setup on your Mac." >&2
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh, then run: brew install transmission-cli" >&2
  exit 1
fi
DAEMON="$(brew --prefix transmission-cli)/bin/transmission-daemon"
if [[ ! -x "$DAEMON" ]]; then
  echo "First run: brew install transmission-cli" >&2
  exit 1
fi
LABEL="local.torrentbar.transmission"
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG="$HOME/Library/Application Support/TorrentBar/Transmission"
LOG_DIR="$HOME/Library/Logs/TorrentBar"
DOWNLOAD_DIR="$HOME/Downloads/Transfers"
# An installed service is left intact. Never modify the native Transmission app,
# a brew-managed service, or any existing torrent configuration.
if ! launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  if lsof -nP -iTCP:9092 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port 9092 is already in use. Nothing was changed. Check: lsof -nP -iTCP:9092 -sTCP:LISTEN" >&2
    exit 1
  fi
  umask 077
  mkdir -p "$HOME/Library/LaunchAgents" "$CONFIG" "$LOG_DIR" "$DOWNLOAD_DIR"
  # plistlib escapes paths correctly, including spaces, ampersands and non-ASCII.
  python3 - "$DAEMON" "$PLIST" "$CONFIG" "$LOG_DIR" "$DOWNLOAD_DIR" <<'PY'
import os, plistlib, sys, tempfile
binary, path, config, logs, downloads = sys.argv[1:]
if not os.path.exists(path):
    job = {
        'Label': 'local.torrentbar.transmission',
        'ProgramArguments': [binary, '--foreground', '--config-dir', config,
            '--rpc-bind-address', '127.0.0.1', '--port', '9092',
            '--allowed', '127.0.0.1', '--no-auth', '--peerport', '51414',
            '--download-dir', downloads],
        'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 15,
        'ProcessType': 'Background',
        'StandardOutPath': os.path.join(logs, 'daemon.log'),
        'StandardErrorPath': os.path.join(logs, 'daemon-error.log')
    }
    fd, temporary = tempfile.mkstemp(dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'wb') as f: plistlib.dump(job, f)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
PY
  plutil -lint "$PLIST"
  launchctl bootstrap "$DOMAIN" "$PLIST"
fi
# A 409 challenge is expected: it proves the RPC listener is answering.
for attempt in {1..15}; do
  STATUS="$(curl --silent --max-time 2 --output /dev/null --write-out '%{http_code}' \
    -H 'Content-Type: application/json' --data '{"method":"session-get"}' \
    http://127.0.0.1:9092/transmission/rpc || true)"
  if [[ "$STATUS" == 409 || "$STATUS" == 200 ]]; then
    printf '\nHeadless Transmission is ready.\nIn TorrentBar Preferences, click Connect to local daemon (9092).\nDownloads: %s\n' "$DOWNLOAD_DIR"
    exit 0
  fi
  sleep 1
done
printf '\nService installed, but RPC is not answering yet. Inspect: %s/daemon-error.log\n' "$LOG_DIR" >&2
exit 1
