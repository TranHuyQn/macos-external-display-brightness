#!/bin/bash
set -euo pipefail

APP_PATH="build/DisplayControl.app"
BIN_PATH="$APP_PATH/Contents/MacOS/DisplayControl"

if [ ! -f "$BIN_PATH" ]; then
    echo "Binary not found at $BIN_PATH. Running build script first..."
    ./scripts/build-app.sh
fi

echo "=========================================================="
echo "           DisplayControl Performance Measure             "
echo "=========================================================="

# 1. App Bundle Size
APP_SIZE_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
APP_SIZE_HUMAN=$(du -sh "$APP_PATH" | awk '{print $1}')
echo "==> 1. App Bundle Size: ${APP_SIZE_KB} KB (${APP_SIZE_HUMAN})"

# 2. Launch App in Background
echo "==> 2. Launching $BIN_PATH in background..."
"$BIN_PATH" > /dev/null 2>&1 &
APP_PID=$!

cleanup() {
    if ps -p "$APP_PID" > /dev/null 2>&1; then
        echo "==> Cleaning up: killing process PID $APP_PID..."
        kill -9 "$APP_PID" > /dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

# Settle down
sleep 2

if ! ps -p "$APP_PID" > /dev/null 2>&1; then
    echo "ERROR: Process exited prematurely"
    exit 1
fi

echo "==> App running with PID: $APP_PID"

# 3. Sample CPU for 60 seconds (idle)
echo "==> 3. Sampling idle CPU for 60 seconds (1 sample/sec)..."
CPU_SAMPLES_FILE=$(mktemp)
for i in $(seq 1 60); do
    if ! ps -p "$APP_PID" > /dev/null 2>&1; then
        echo "ERROR: Process died during sampling at second $i"
        exit 1
    fi
    CPU=$(ps -o %cpu= -p "$APP_PID" | tr -d ' ')
    echo "${CPU:-0.0}" >> "$CPU_SAMPLES_FILE"
    sleep 1
done

CPU_STATS=$(awk '{
    sum += $1
    if (NR == 1 || $1 > max) max = $1
} END {
    if (NR > 0) {
        printf "Avg: %.2f%%, Max: %.1f%% (%d samples)", sum/NR, max, NR
    } else {
        printf "No samples"
    }
}' "$CPU_SAMPLES_FILE")
rm -f "$CPU_SAMPLES_FILE"
echo "    CPU Idle Stats: $CPU_STATS"

# 4. Memory Footprint (footprint -p and RSS)
echo "==> 4. Measuring memory footprint..."
FOOTPRINT_OUTPUT=$(footprint -p "$APP_PID" 2>&1 || true)
PHYS_FOOTPRINT=$(echo "$FOOTPRINT_OUTPUT" | grep -E "phys_footprint:" | head -n 1 | awk '{$1=""; print $0}' | sed 's/^ //')
PEAK_FOOTPRINT=$(echo "$FOOTPRINT_OUTPUT" | grep -E "phys_footprint_peak:" | head -n 1 | awk '{$1=""; print $0}' | sed 's/^ //')
TOTAL_FOOTPRINT=$(echo "$FOOTPRINT_OUTPUT" | grep -E "^sleep|^DisplayControl" | head -n 1 | sed -E 's/.*Footprint: ([^()]+).*/\1/' | sed 's/ $//')

RSS_KB=$(ps -o rss= -p "$APP_PID" | tr -d ' ')
RSS_MB=$(awk "BEGIN {printf \"%.1f\", $RSS_KB / 1024}")

echo "    Physical Footprint: ${PHYS_FOOTPRINT:-$TOTAL_FOOTPRINT} (Peak: ${PEAK_FOOTPRINT:-N/A})"
echo "    RSS (for reference): ${RSS_KB} KB (${RSS_MB} MB)"

echo "=========================================================="
echo "                     Summary Report                       "
echo "=========================================================="
echo "- App Bundle Size:    ${APP_SIZE_KB} KB (${APP_SIZE_HUMAN}) [Target: < 2 MB]"
echo "- CPU Idle:           ${CPU_STATS} [Target: Avg 0.0%, Max < 0.5%]"
echo "- Physical Footprint: ${PHYS_FOOTPRINT:-$TOTAL_FOOTPRINT} [Target: < 25 MB]"
echo "- RSS (reference):    ${RSS_MB} MB"
echo "=========================================================="
