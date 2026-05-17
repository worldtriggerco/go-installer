#!/data/data/com.termux/files/usr/bin/bash

set -u

APP_NAME="GO"
APP_VERSION="v1.6.0"
ARCHIVE_NAME="GO-v1.6.0.7z"
ARCHIVE_URL="https://familynor.ir/GO-v1.6.0.7z"

ARCHIVE_PASS="${1:-}"

if [ -z "$ARCHIVE_PASS" ]; then
  echo "Usage:"
  echo "bash <(curl -fsSL URL) PASSWORD"
  exit 1
fi

APP_DIR="$HOME/$APP_NAME"
PASS_FILE="$APP_DIR/.archive_pass"
OLD_DIR="$HOME/GO-old"
TMP_DIR="$HOME/GO-install-tmp"
EXTRACT_DIR="$TMP_DIR/GO-v1.6.0"

echo "Installing GooseRelayVPN..."

pkg update -y
pkg install wget p7zip termux-api procps curl grep sed coreutils iproute2 socat -y

echo "Downloading package..."

rm -rf "$TMP_DIR"
rm -f "$HOME/$ARCHIVE_NAME"
mkdir -p "$TMP_DIR"

cd "$HOME" || exit 1

wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"

if [ ! -s "$HOME/$ARCHIVE_NAME" ]; then
  echo "ERROR: download failed or file is empty."
  rm -rf "$TMP_DIR"
  rm -f "$HOME/$ARCHIVE_NAME"
  exit 1
fi

echo "Extracting package..."

7z x -y -p"$ARCHIVE_PASS" "$HOME/$ARCHIVE_NAME" -o"$TMP_DIR" || {
  echo "ERROR: wrong password or extraction failed."
  rm -rf "$TMP_DIR"
  rm -f "$HOME/$ARCHIVE_NAME"
  exit 1
}

rm -f "$HOME/$ARCHIVE_NAME"

if [ ! -d "$EXTRACT_DIR" ]; then
  echo "ERROR: extracted folder not found: $EXTRACT_DIR"
  rm -rf "$TMP_DIR"
  exit 1
fi

if [ ! -f "$EXTRACT_DIR/goose-client" ]; then
  echo "ERROR: goose-client not found."
  rm -rf "$TMP_DIR"
  exit 1
fi

if [ ! -f "$EXTRACT_DIR/client_config.json" ]; then
  echo "ERROR: client_config.json not found."
  rm -rf "$TMP_DIR"
  exit 1
fi

echo "Stopping old Goose..."
pkill -f goose-client 2>/dev/null || true
pkill -f goose-watch.sh 2>/dev/null || true
pkill -f goose-gate.sh 2>/dev/null || true
pkill -f goose-handle.sh 2>/dev/null || true
pkill -f "socat.*1080" 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true

echo "Replacing old installation..."

rm -rf "$OLD_DIR"

if [ -d "$APP_DIR" ]; then
  mv "$APP_DIR" "$OLD_DIR"
fi

mv "$EXTRACT_DIR" "$APP_DIR"

echo "$ARCHIVE_PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"

rm -rf "$TMP_DIR"
rm -rf "$OLD_DIR"
rm -f "$PREFIX/bin/goose"

cd "$APP_DIR" || exit 1
chmod +x goose-client

cat > goose-handle.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

touch goose.log

if ! pgrep -f goose-client >/dev/null; then
  termux-wake-lock 2>/dev/null || true
  echo "$(date '+%H:%M:%S') AUTO START - connection received on 1080" >> goose.log
  nohup ./goose-client -config client_config.json >> goose.log 2>&1 &
fi

TRIES=0
while [ "$TRIES" -lt 20 ]; do
  if ss -ltn 2>/dev/null | grep -q ':1081'; then
    break
  fi
  TRIES=$((TRIES + 1))
  sleep 0.5
done

exec socat STDIO TCP:127.0.0.1:1081
EOF

cat > goose-gate.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

pkill -f "socat.*1080" 2>/dev/null || true

echo "$(date '+%H:%M:%S') GATE STARTED - listening on 127.0.0.1:1080, forwarding to Goose 1081" >> goose.log

exec socat TCP-LISTEN:1080,bind=127.0.0.1,reuseaddr,fork EXEC:"$HOME/GO/goose-handle.sh"
EOF

cat > goose-watch.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

IDLE_LIMIT_SECONDS=600
CHECK_SECONDS=15
LAST_ACTIVE_FILE="$HOME/GO/.last_socks_activity"

date +%s > "$LAST_ACTIVE_FILE"

while true; do
  GATE_ACTIVE="$(ss -tn 2>/dev/null | grep -E ':1080|:1081' | grep ESTAB | wc -l | tr -d ' ')"

  if [ "$GATE_ACTIVE" -gt 0 ]; then
    date +%s > "$LAST_ACTIVE_FILE"
  else
    LAST_ACTIVE="$(cat "$LAST_ACTIVE_FILE" 2>/dev/null || echo 0)"
    NOW_TIME="$(date +%s)"
    IDLE_TIME=$((NOW_TIME - LAST_ACTIVE))

    if [ "$IDLE_TIME" -ge "$IDLE_LIMIT_SECONDS" ]; then
      if pgrep -f goose-client >/dev/null; then
        echo "$(date '+%H:%M:%S') AUTO STOP - no active SOCKS connection for 10 minutes" >> goose.log
        pkill -f goose-client 2>/dev/null || true
        termux-wake-unlock 2>/dev/null || true
      fi
    fi
  fi

  sleep "$CHECK_SECONDS"
done
EOF

cat > goose-on.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

pkill -f goose-client 2>/dev/null || true
pkill -f goose-watch.sh 2>/dev/null || true
pkill -f goose-gate.sh 2>/dev/null || true
pkill -f goose-handle.sh 2>/dev/null || true
pkill -f "socat.*1080" 2>/dev/null || true

rm -f goose.log
rm -f .last_socks_activity

date +%s > "$HOME/GO/.last_socks_activity"

nohup ./goose-gate.sh > /dev/null 2>&1 &
nohup ./goose-watch.sh > /dev/null 2>&1 &

sleep 2

if ! pgrep -f goose-gate.sh >/dev/null && ! ss -ltn 2>/dev/null | grep -q ':1080'; then
  clear
  echo ""
  echo "======================================="
  echo "            GOOSE GATE FAILED"
  echo "======================================="
  echo ""
  tail -n 40 goose.log 2>/dev/null
  exit 1
fi

while true; do
  clear

  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣄⡀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⣏⣹⣿⠄⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⠿⠋⢠⣷⣦⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣆⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣶⣿⣿⣿⠛⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣾⣿⣿⣿⣿⣿⣿⡇⢸⣿⣿⣿⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⢸⣿⣿⡿⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⢀⣠⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠋⣠⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠰⢾⣿⣿⣿⡟⠿⠿⣿⣿⠿⠿⠛⠋⣁⣴⣾⣿⣿⠿⠋⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠉⠛⠻⠷⣶⣤⣤⣤⣤⣶⣾⣿⡿⠿⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⢀⣶⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
  echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠛⠛⠛⠛⠛⠂⠀⠀⠀⠀"
  echo ""
  echo "======================================="
  echo "          GOOSE RELAY GATE ONLINE"
  echo "======================================="
  echo ""
  echo "PUBLIC SOCKS5 ADDRESS:"
  echo ""
  echo "          127.0.0.1:1080"
  echo ""
  echo "GOOSE INTERNAL SOCKS:"
  echo ""
  echo "          127.0.0.1:1081"
  echo ""

  if ss -ltn 2>/dev/null | grep -q ':1080'; then
    GATE_STATUS="RUNNING"
  else
    GATE_STATUS="OFF"
  fi

  if pgrep -f goose-client >/dev/null; then
    CLIENT_STATUS="RUNNING"
  else
    CLIENT_STATUS="AUTO STOPPED - WAITING FOR SOCKS USE"
  fi

  ACTIVE_CONN="$(ss -tn 2>/dev/null | grep -E ':1080|:1081' | grep ESTAB | wc -l | tr -d ' ')"

  echo "AUTO CONTROL STATUS:"
  echo ""
  echo "          GATE STATUS       : $GATE_STATUS"
  echo "          CLIENT STATUS     : $CLIENT_STATUS"
  echo "          ACTIVE CONNECTIONS: $ACTIVE_CONN"
  echo "          AUTO STOP AFTER   : 10 IDLE MINUTES"
  echo ""

  STATS_LINE="$(grep 'endpoints=' goose.log 2>/dev/null | tail -n 1)"

  if echo "$STATS_LINE" | grep -q 'endpoints='; then
    ENDPOINTS="$(echo "$STATS_LINE" | sed -n 's/.*endpoints=\([0-9]*\/[0-9]*\).*/\1/p')"
    ONLINE="$(echo "$ENDPOINTS" | cut -d/ -f1)"
    TOTAL="$(echo "$ENDPOINTS" | cut -d/ -f2)"
    OFFLINE=$((TOTAL - ONLINE))

    echo "GOOGLE ACCOUNTS STATUS:"
    echo ""
    echo "          WORKING : $ONLINE / $TOTAL"
    echo "          OFFLINE : $OFFLINE / $TOTAL"
    echo ""
  else
    echo "GOOGLE ACCOUNTS STATUS:"
    echo ""
    echo "          WAITING FOR STATS..."
    echo ""
  fi

  FAIL403="$(grep -c 'HTTP 403' goose.log 2>/dev/null || true)"
  BLACKLISTED="$(grep -c 'blacklisted' goose.log 2>/dev/null || true)"
  NETFAIL="$(grep -c 'network is unreachable' goose.log 2>/dev/null || true)"
  RECOVERED="$(grep -c 'recovered' goose.log 2>/dev/null || true)"

  echo "ERROR COUNTERS:"
  echo ""
  echo "          HTTP 403          : $FAIL403"
  echo "          BLACKLISTED       : $BLACKLISTED"
  echo "          NETWORK FAILURES  : $NETFAIL"
  echo "          RECOVERED         : $RECOVERED"
  echo ""
  echo ""
  echo "======================================="
  echo "Press CTRL + C to exit live monitor"
  echo "Gate keeps running in background"
  echo "Goose client auto starts/stops"
  echo "======================================="
  echo ""

  sleep 5
done
EOF

cat > goose-off.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

clear

pkill -f goose-client 2>/dev/null || true
pkill -f goose-watch.sh 2>/dev/null || true
pkill -f goose-gate.sh 2>/dev/null || true
pkill -f goose-handle.sh 2>/dev/null || true
pkill -f "socat.*1080" 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true

echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡤⠒⠒⠢⢄⡀⠀⠀⢠⡏⠉⠉⠉⠑⠒⠤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡞⠀⠀⠀⠀⠀⠙⢦⠀⡇⡇⠀⠀⠀⠀⠀⠀⠈⠱⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠊⠉⠉⠙⠒⢤⡀⠀⣼⠀⠀⢀⣶⣤⠀⠀⠀⢣⡇⡇⠀⠀⢴⣶⣦⠀⠀⠀⢳⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⠀⠀⠀⢀⣠⠤⢄⠀⠀⢰⡇⠀⠀⣠⣀⠀⠀⠈⢦⡿⡀⠀⠈⡟⣟⡇⠀⠀⢸⡇⡆⠀⠀⡼⢻⣠⠀⠀⠀⣸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⠀⢀⠖⠉⠀⠀⠀⣱⡀⡞⡇⠀⠀⣿⣿⢣⠀⠀⠈⣧⣣⠀⠀⠉⠋⠀⠀⠀⣸⡇⠇⠀⠀⠈⠉⠀⠀⠀⢀⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⣠⠏⠀⠀⣴⢴⣿⣿⠗⢷⡹⡀⠀⠘⠾⠾⠀⠀⠀⣿⣿⣧⡀⠀⠀⠀⢀⣴⠇⣇⣆⣀⢀⣀⣀⣀⣀⣤⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⣿⠀⠀⢸⢻⡞⠋⠀⠀⠀⢿⣷⣄⠀⠀⠀⠀⠀⣠⡇⠙⢿⣽⣷⣶⣶⣿⠋⢰⣿⣿⣿⣿⣿⣿⠿⠛⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
echo "⡿⡄⠀⠈⢻⣝⣶⣶⠀⠀⠀⣿⣿⣱⣶⣶⣶⣾⡟⠀⠀⠀⢈⡉⠉⢩⡖⠒⠈⠉⡏⡴⡏⠉⠉⠉⠉⠉⠉⠉⠉⡇⠀⠀⢀⣴⠒⠢⠤⣀"
echo "⢣⣸⣆⡀⠀⠈⠉⠁⠀⠀⣠⣷⠈⠙⠛⠛⠛⠉⢀⣴⡊⠉⠁⠈⢢⣿⠀⠀⠀⢸⠡⠀⠁⠀⠀⠀⣠⣀⣀⣀⣀⡇⠀⢰⢁⡇⠀⠀⠀⢠"
echo "⠀⠻⣿⣟⢦⣤⡤⣤⣴⣾⡿⢃⡠⠔⠒⠉⠛⠢⣾⢿⣿⣦⡀⠀⠀⠉⠀⠀⢀⡇⢸⠀⠀⠀⠀⠀⠿⠿⠿⣿⡟⠀⢀⠇⢸⠀⠀⠀⠀⠘"
echo "⠀⠀⠈⠙⠛⠿⠿⠿⠛⠋⢰⡋⠀⠀⢠⣤⡄⠀⠈⡆⠙⢿⣿⣦⣀⠀⠀⠀⣜⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⢀⠃⠀⡸⠀⠇⠀⠀⠀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⢣⠀⠀⠈⠛⠁⠀⢴⠥⡀⠀⠙⢿⡿⡆⠀⠀⢸⠀⢸⢰⠀⠀⠀⢀⣿⣶⣶⡾⠀⢀⠇⣸⠀⠀⠀⠀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⡀⢇⠀⠀⠀⢀⡀⠀⠀⠈⢢⠀⠀⢃⢱⠀⠀⠀⡇⢸⢸⠀⠀⠀⠈⠉⠉⠉⢱⠀⠼⣾⣿⣿⣷⣦⠴⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢱⠘⡄⠀⠀⢹⣿⡇⠀⠀⠈⡆⠀⢸⠈⡇⢀⣀⣵⢨⣸⣦⣤⣤⣄⣀⣀⣀⡞⠀⣠⡞⠉⠈⠉⢣⡀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢃⠘⡄⠀⠀⠉⠀⠀⣠⣾⠁⠀⠀⣧⣿⣿⡿⠃⠸⠿⣿⣿⣿⣿⣿⣿⠟⠁⣼⣾⠀⠀⠀⠀⢠⠇⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡄⠹⣀⣀⣤⣶⣿⡿⠃⠀⠀⠀⠈⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠁⠀⠀⢻⣿⣷⣦⣤⣤⠎⠀⠀⠀"
echo "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣤⣿⡿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠀⠀⠀⠀⠀"
echo ""
echo "======================================="
echo "            GOOSE RELAY OFF"
echo "======================================="
echo ""
EOF

cat > goose-update.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -u

APP_NAME="GO"
APP_VERSION="v1.6.0"
ARCHIVE_NAME="GO-v1.6.0.7z"
ARCHIVE_URL="https://familynor.ir/GO-v1.6.0.7z"

APP_DIR="$HOME/$APP_NAME"
PASS_FILE="$APP_DIR/.archive_pass"
TMP_DIR="$HOME/GO-update-tmp"
EXTRACT_DIR="$TMP_DIR/GO-v1.6.0"

clear
echo "Updating GooseRelayVPN..."

if [ ! -f "$PASS_FILE" ]; then
  echo "ERROR: saved password not found."
  echo "Please reinstall once with password."
  exit 1
fi

ARCHIVE_PASS="$(cat "$PASS_FILE")"

cd "$HOME" || exit 1

rm -rf "$TMP_DIR"
rm -f "$HOME/$ARCHIVE_NAME"
mkdir -p "$TMP_DIR"

echo "Downloading latest package..."
wget -O "$ARCHIVE_NAME" "$ARCHIVE_URL"

if [ ! -s "$HOME/$ARCHIVE_NAME" ]; then
  echo "ERROR: download failed or file is empty."
  rm -rf "$TMP_DIR"
  rm -f "$HOME/$ARCHIVE_NAME"
  exit 1
fi

echo "Extracting package..."

7z x -y -p"$ARCHIVE_PASS" "$HOME/$ARCHIVE_NAME" -o"$TMP_DIR" || {
  echo "ERROR: wrong saved password or extraction failed."
  rm -rf "$TMP_DIR"
  rm -f "$HOME/$ARCHIVE_NAME"
  exit 1
}

rm -f "$HOME/$ARCHIVE_NAME"

if [ ! -d "$EXTRACT_DIR" ]; then
  echo "ERROR: extracted folder not found: $EXTRACT_DIR"
  rm -rf "$TMP_DIR"
  exit 1
fi

if [ ! -f "$EXTRACT_DIR/goose-client" ]; then
  echo "ERROR: goose-client not found."
  rm -rf "$TMP_DIR"
  exit 1
fi

if [ ! -f "$EXTRACT_DIR/client_config.json" ]; then
  echo "ERROR: client_config.json not found."
  rm -rf "$TMP_DIR"
  exit 1
fi

echo "Stopping Goose..."
pkill -f goose-client 2>/dev/null || true
pkill -f goose-watch.sh 2>/dev/null || true
pkill -f goose-gate.sh 2>/dev/null || true
pkill -f goose-handle.sh 2>/dev/null || true
pkill -f "socat.*1080" 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true

echo "Replacing files..."

cp -f "$EXTRACT_DIR/goose-client" "$APP_DIR/goose-client"
cp -f "$EXTRACT_DIR/client_config.json" "$APP_DIR/client_config.json"

chmod +x "$APP_DIR/goose-client"

rm -rf "$TMP_DIR"

echo ""
echo "Update complete"
echo "Run:"
echo "goose on"
echo ""
EOF

chmod +x goose-on.sh goose-off.sh goose-update.sh goose-watch.sh goose-gate.sh goose-handle.sh

mkdir -p "$PREFIX/bin"

cat > "$PREFIX/bin/goose" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

case "$1" in
  on)
    "$HOME/GO/goose-on.sh"
    ;;
  off)
    "$HOME/GO/goose-off.sh"
    ;;
  restart)
    "$HOME/GO/goose-off.sh"
    sleep 1
    "$HOME/GO/goose-on.sh"
    ;;
  update)
    "$HOME/GO/goose-update.sh"
    ;;
  status)
    if ss -ltn 2>/dev/null | grep -q ':1080'; then
      echo "Gate is ON"
      echo "Public SOCKS5: 127.0.0.1:1080"
    else
      echo "Gate is OFF"
    fi

    if pgrep -f goose-client >/dev/null; then
      echo "Goose client is ON"
      echo "Internal SOCKS5: 127.0.0.1:1081"
    else
      echo "Goose client is AUTO STOPPED"
    fi
    ;;
  logs)
    tail -f "$HOME/GO/goose.log"
    ;;
  monitor)
    "$HOME/GO/goose-on.sh"
    ;;
  test)
    curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
    ;;
  *)
    echo "Usage:"
    echo "goose on"
    echo "goose off"
    echo "goose restart"
    echo "goose update"
    echo "goose status"
    echo "goose logs"
    echo "goose test"
    ;;
esac
EOF

chmod +x "$PREFIX/bin/goose"

echo ""
echo "Installation complete"
echo "Commands:"
echo "goose on"
echo "goose off"
echo "goose restart"
echo "goose update"
echo "goose status"
echo "goose logs"
echo "goose test"
