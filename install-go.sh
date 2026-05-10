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
OLD_DIR="$HOME/GO-old"
TMP_DIR="$HOME/GO-install-tmp"
EXTRACT_DIR="$TMP_DIR/GO-v1.6.0"

echo "Installing GooseRelayVPN..."

pkg update -y
pkg install wget p7zip termux-api procps curl -y

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
termux-wake-unlock 2>/dev/null || true

echo "Replacing old installation..."

rm -rf "$OLD_DIR"

if [ -d "$APP_DIR" ]; then
  mv "$APP_DIR" "$OLD_DIR"
fi

mv "$EXTRACT_DIR" "$APP_DIR"

rm -rf "$TMP_DIR"
rm -rf "$OLD_DIR"
rm -f "$PREFIX/bin/goose"

cd "$APP_DIR" || exit 1
chmod +x goose-client

cat > goose-on.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

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
echo "Starting GooseRelay..."

cd "$HOME/GO" || exit 1

termux-wake-lock 2>/dev/null || true
pkill -f goose-client 2>/dev/null || true
rm -f goose.log

nohup ./goose-client -config client_config.json > goose.log 2>&1 &

sleep 4

if pgrep -f goose-client >/dev/null; then
  echo ""
  echo "======================================="
  echo "          GOOSE RELAY ONLINE"
  echo "======================================="
  echo ""
  echo "SOCKS5 ADDRESS:"
  echo ""
  echo "          127.0.0.1:1080"
  echo ""
  echo "Use: goose logs"
  echo ""
else
  echo ""
  echo "======================================="
  echo "            GOOSE FAILED"
  echo "======================================="
  echo ""
  echo "Last logs:"
  tail -n 40 goose.log 2>/dev/null
fi
EOF

cat > goose-off.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

clear

pkill -f goose-client 2>/dev/null || true
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

chmod +x goose-on.sh goose-off.sh

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
  test)
    curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
    ;;
  *)
    echo "Usage:"
    echo "goose on"
    echo "goose off"
    echo "goose restart"
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
echo "goose status"
echo "goose logs"
echo "goose test"
