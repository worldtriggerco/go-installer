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
pkg install wget p7zip termux-api procps curl grep sed coreutils iproute2 -y

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

cat > goose-watch.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

IDLE_LIMIT_SECONDS=600
CHECK_SECONDS=15
LAST_ACTIVE_FILE="$HOME/GO/.last_socks_activity"
STATE_FILE="$HOME/GO/.goose_state"

notify_goose() {
  TITLE="$1"
  MSG="$2"

  if command -v termux-notification >/dev/null 2>&1; then
    termux-notification \
      --title "$TITLE" \
      --content "$MSG" \
      --priority high >/dev/null 2>&1 || true
  fi
}

date +%s > "$LAST_ACTIVE_FILE"
echo "RUNNING" > "$STATE_FILE"

while true; do
  ACTIVE_CONN="$(ss -tn 2>/dev/null | grep ':1080' | grep ESTAB | wc -l | tr -d ' ')"

  if [ "$ACTIVE_CONN" -gt 0 ]; then
    date +%s > "$LAST_ACTIVE_FILE"

    if ! pgrep -f goose-client >/dev/null; then
      termux-wake-lock 2>/dev/null || true
      echo "RUNNING" > "$STATE_FILE"
      echo "$(date '+%H:%M:%S') AUTO START - SOCKS activity detected" >> goose.log
      notify_goose "GooseRelayVPN" "Goose started automatically"
      nohup ./goose-client -config client_config.json >> goose.log 2>&1 &
    else
      echo "RUNNING" > "$STATE_FILE"
    fi
  else
    LAST_ACTIVE="$(cat "$LAST_ACTIVE_FILE" 2>/dev/null || echo 0)"
    NOW_TIME="$(date +%s)"
    IDLE_TIME=$((NOW_TIME - LAST_ACTIVE))

    if [ "$IDLE_TIME" -ge "$IDLE_LIMIT_SECONDS" ]; then
      if pgrep -f goose-client >/dev/null; then
        echo "$(date '+%H:%M:%S') AUTO STOP - no SOCKS activity for 10 minutes" >> goose.log
        echo "AUTO STOPPED" > "$STATE_FILE"
        notify_goose "GooseRelayVPN" "Goose stopped after 10 minutes idle"
        pkill -f goose-client 2>/dev/null || true
        termux-wake-unlock 2>/dev/null || true
      else
        echo "AUTO STOPPED" > "$STATE_FILE"
      fi
    fi
  fi

  sleep "$CHECK_SECONDS"
done
EOF

cat > goose-on.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

termux-wake-lock 2>/dev/null || true
pkill -f goose-client 2>/dev/null || true
pkill -f goose-watch.sh 2>/dev/null || true
rm -f goose.log
rm -f .last_socks_activity
rm -f .goose_state

date +%s > "$HOME/GO/.last_socks_activity"
echo "RUNNING" > "$HOME/GO/.goose_state"

nohup ./goose-client -config client_config.json > goose.log 2>&1 &
nohup ./goose-watch.sh > /dev/null 2>&1 &

if command -v termux-notification >/dev/null 2>&1; then
  termux-notification \
    --title "GooseRelayVPN" \
    --content "Goose started manually" \
    --priority high >/dev/null 2>&1 || true
fi

sleep 4

if ! pgrep -f goose-client >/dev/null; then
  clear
  echo ""
  echo "======================================="
  echo "            GOOSE FAILED"
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
  echo "          GOOSE RELAY ONLINE"
  echo "======================================="
  echo ""
  echo "SOCKS5 ADDRESS:"
  echo ""
  echo "          127.0.0.1:1080"
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

  ACTIVE_CONN="$(ss -tn 2>/dev/null | grep ':1080' | grep ESTAB | wc -l | tr -d ' ')"

  if pgrep -f goose-client >/dev/null; then
    CLIENT_STATE="RUNNING"
  else
    CLIENT_STATE="$(cat "$HOME/GO/.goose_state" 2>/dev/null || echo "AUTO STOPPED")"
  fi

  echo "AUTO CONTROL STATUS:"
  echo ""
  echo "          CLIENT STATUS      : $CLIENT_STATE"
  echo "          ACTIVE SOCKS CONN  : $ACTIVE_CONN"
  echo "          AUTO STOP AFTER    : 10 IDLE MINUTES"
  echo "          NOTIFICATION       : ENABLED"
  echo ""

  echo ""
  echo "======================================="
  echo "Press CTRL + C to exit live monitor"
  echo "Goose keeps running in background"
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
termux-wake-unlock 2>/dev/null || true

echo "OFF" > "$HOME/GO/.goose_state" 2>/dev/null || true

if command -v termux-notification >/dev/null 2>&1; then
  termux-notification \
    --title "GooseRelayVPN" \
    --content "Goose stopped manually" \
    --priority high >/dev/null 2>&1 || true
fi

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

chmod +x goose-on.sh goose-off.sh goose-update.sh goose-watch.sh

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
    if pgrep -f goose-client >/dev/null; then
      echo "Goose is ON"
      echo "SOCKS5: 127.0.0.1:1080"
    else
      echo "Goose is OFF"
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
