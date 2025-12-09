!/bin/bash

# Hook script for earlyoom to restart polkitd when it exceeds 12% of available memory
THRESHOLD_PERCENT=12

# Get polkitd PID safely
POLKIT_PID=$(pgrep -o polkitd 2>/dev/null)

if [ -z "$POLKIT_PID" ]; then
    echo "[polkitd-hook] Error: polkitd process not found"
    exit 0  # Exit cleanly if polkitd isn't running
fi

# Get polkitd memory usage (RSS in KB) - more robust method
if [ -f "/proc/$POLKIT_PID/status" ]; then
    POLKIT_RSS_KB=$(grep VmRSS "/proc/$POLKIT_PID/status" | awk '{print $2}')
else
    # Fallback to ps if /proc method fails
    POLKIT_RSS_KB=$(ps -o rss= -p "$POLKIT_PID" 2>/dev/null | awk '{print $1}')
fi

# Get total available memory in KB
if [ -f "/proc/meminfo" ]; then
    TOTAL_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
else
    TOTAL_MEM_KB=$(free -k | awk '/^Mem:/{print $7}')
fi

# Validate values
if [ -z "$POLKIT_RSS_KB" ] || [ -z "$TOTAL_MEM_KB" ] || [ "$TOTAL_MEM_KB" -le 0 ]; then
    echo "[polkitd-hook] Error: Could not read memory values (RSS: $POLKIT_RSS_KB, Available: $TOTAL_MEM_KB KB)"
    exit 0
fi

# Calculate percentage
POLKIT_PERCENT=$(( (POLKIT_RSS_KB * 100) / TOTAL_MEM_KB ))

echo "[polkitd-hook] polkitd(PID:$POLKIT_PID) uses ${POLKIT_RSS_KB}KB (${POLKIT_PERCENT}% of ${TOTAL_MEM_KB}KB available)"

if [ "$POLKIT_PERCENT" -gt "$THRESHOLD_PERCENT" ]; then
    echo "[polkitd-hook] Threshold exceeded (${POLKIT_PERCENT}% > ${THRESHOLD_PERCENT}%). Restarting polkit.service..."
    systemctl restart polkit.service
    echo "[polkitd-hook] Restart command issued at $(date)"
fi