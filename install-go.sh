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
pkg install wget p7zip termux-api procps curl grep sed coreutils golang -y

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
pkill -f goose-gate-go 2>/dev/null || true
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

cat > goose-gate.go << 'EOF'
package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

const (
	publicListen       = "127.0.0.1:1080"
	internalGoose     = "127.0.0.1:1081"
	idleLimitSeconds  = 600
	checkEverySeconds = 5
)

var activeConnections int64
var lastActiveUnix int64

func writeFile(name string, value string) {
	_ = os.WriteFile(name, []byte(value), 0644)
}

func appendLog(msg string) {
	f, err := os.OpenFile("goose.log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	now := time.Now().Format("15:04:05")
	_, _ = f.WriteString(now + " " + msg + "\n")
}

func processRunning(name string) bool {
	cmd := exec.Command("pgrep", "-f", name)
	err := cmd.Run()
	return err == nil
}

func startGoose() {
	if processRunning("goose-client") {
		return
	}

	appendLog("AUTO START - starting goose-client on internal 1081")
	_ = exec.Command("termux-wake-lock").Run()

	cmd := exec.Command("./goose-client", "-config", "client_config.json")
	logFile, err := os.OpenFile("goose.log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err == nil {
		cmd.Stdout = logFile
		cmd.Stderr = logFile
	}
	_ = cmd.Start()
}

func stopGoose() {
	if !processRunning("goose-client") {
		return
	}

	appendLog("AUTO STOP - no active SOCKS connection for 10 minutes")
	_ = exec.Command("pkill", "-f", "goose-client").Run()
	_ = exec.Command("termux-wake-unlock").Run()
}

func countdownLoop() {
	for {
		active := atomic.LoadInt64(&activeConnections)

		if active > 0 {
			atomic.StoreInt64(&lastActiveUnix, time.Now().Unix())
			writeFile(".idle_countdown", strconv.Itoa(idleLimitSeconds))
		} else {
			last := atomic.LoadInt64(&lastActiveUnix)
			idle := int(time.Now().Unix() - last)
			left := idleLimitSeconds - idle
			if left < 0 {
				left = 0
			}
			writeFile(".idle_countdown", strconv.Itoa(left))

			if idle >= idleLimitSeconds {
				stopGoose()
			}
		}

		writeFile(".active_connections", strconv.FormatInt(active, 10))

		if processRunning("goose-client") {
			writeFile(".client_state", "RUNNING")
		} else {
			writeFile(".client_state", "AUTO STOPPED - WAITING FOR SOCKS USE")
		}

		time.Sleep(time.Duration(checkEverySeconds) * time.Second)
	}
}

func pipe(dst net.Conn, src net.Conn) {
	_, _ = io.Copy(dst, src)
	_ = dst.Close()
	_ = src.Close()
}

func handleConn(client net.Conn) {
	atomic.AddInt64(&activeConnections, 1)
	atomic.StoreInt64(&lastActiveUnix, time.Now().Unix())
	writeFile(".idle_countdown", strconv.Itoa(idleLimitSeconds))
	writeFile(".active_connections", strconv.FormatInt(atomic.LoadInt64(&activeConnections), 10))

	appendLog("GATE CONNECTION - request received on 1080")

	startGoose()

	var upstream net.Conn
	var err error

	for i := 0; i < 30; i++ {
		upstream, err = net.DialTimeout("tcp", internalGoose, 2*time.Second)
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
	}

	if err != nil {
		appendLog("GATE ERROR - cannot connect to internal Goose 1081: " + err.Error())
		_ = client.Close()
		atomic.AddInt64(&activeConnections, -1)
		writeFile(".active_connections", strconv.FormatInt(atomic.LoadInt64(&activeConnections), 10))
		return
	}

	go pipe(upstream, client)
	go pipe(client, upstream)

	for {
		time.Sleep(1 * time.Second)
		if strings.Contains(fmt.Sprintf("%v", client), "<nil>") {
			break
		}
	}

	atomic.AddInt64(&activeConnections, -1)
	if atomic.LoadInt64(&activeConnections) < 0 {
		atomic.StoreInt64(&activeConnections, 0)
	}
	writeFile(".active_connections", strconv.FormatInt(atomic.LoadInt64(&activeConnections), 10))
}

func main() {
	atomic.StoreInt64(&lastActiveUnix, time.Now().Unix())
	writeFile(".idle_countdown", strconv.Itoa(idleLimitSeconds))
	writeFile(".active_connections", "0")
	writeFile(".client_state", "AUTO STOPPED - WAITING FOR SOCKS USE")

	appendLog("GATE STARTED - listening on 127.0.0.1:1080, forwarding to Goose 1081")

	listener, err := net.Listen("tcp", publicListen)
	if err != nil {
		appendLog("GATE FAILED - " + err.Error())
		os.Exit(1)
	}

	go countdownLoop()

	for {
		conn, err := listener.Accept()
		if err != nil {
			appendLog("GATE ACCEPT ERROR - " + err.Error())
			continue
		}
		go handleConn(conn)
	}
}
EOF

echo "Building lightweight Go gate..."
go build -o goose-gate-go goose-gate.go || {
  echo "ERROR: failed to build goose-gate-go"
  exit 1
}

chmod +x goose-gate-go

cat > goose-on.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/GO" || exit 1

termux-wake-lock 2>/dev/null || true
pkill -f goose-client 2>/dev/null || true
pkill -f goose-gate-go 2>/dev/null || true

rm -f goose.log
rm -f .idle_countdown
rm -f .active_connections
rm -f .client_state

echo "600" > .idle_countdown
echo "0" > .active_connections
echo "AUTO STOPPED - WAITING FOR SOCKS USE" > .client_state

nohup ./goose-gate-go > /dev/null 2>&1 &

sleep 3

if ! pgrep -f goose-gate-go >/dev/null; then
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

  if pgrep -f goose-gate-go >/dev/null; then
    GATE_STATUS="RUNNING"
  else
    GATE_STATUS="OFF"
  fi

  if pgrep -f goose-client >/dev/null; then
    CLIENT_STATUS="RUNNING"
  else
    CLIENT_STATUS="$(cat .client_state 2>/dev/null || echo 'AUTO STOPPED - WAITING FOR SOCKS USE')"
  fi

  ACTIVE_CONN="$(cat .active_connections 2>/dev/null || echo 0)"
  LEFT_TIME="$(cat .idle_countdown 2>/dev/null || echo 600)"
  LEFT_MIN=$((LEFT_TIME / 60))
  LEFT_SEC=$((LEFT_TIME % 60))

  echo "AUTO CONTROL STATUS:"
  echo ""
  echo "          GATE STATUS       : $GATE_STATUS"
  echo "          CLIENT STATUS     : $CLIENT_STATUS"
  echo "          ACTIVE CONNECTIONS: $ACTIVE_CONN"
  echo "          AUTO STOP TIMER   : ${LEFT_MIN}m ${LEFT_SEC}s"
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
pkill -f goose-gate-go 2>/dev/null || true
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
pkill -f goose-gate-go 2>/dev/null || true
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

chmod +x goose-on.sh goose-off.sh goose-update.sh goose-gate-go

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
    if pgrep -f goose-gate-go >/dev/null; then
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
