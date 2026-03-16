#!/bin/bash
# work-pulse-guard.sh
# Prevents overlapping work pulses. Run at the start of every work cycle.
# Returns 0 + "LOCK ACQUIRED" if safe to proceed.
# Returns 1 + "LOCKED" if another pulse is running.

LOCK_FILE="/tmp/ercole-work-pulse.lock"
MAX_AGE_SECONDS=720  # 12 minutes - gives 3 min buffer before next 15-min pulse

if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE") ))
    if [ "$LOCK_AGE" -lt "$MAX_AGE_SECONDS" ]; then
        echo "LOCKED - another pulse is running (age: ${LOCK_AGE}s)"
        exit 1
    else
        echo "STALE LOCK - removing (age: ${LOCK_AGE}s)"
        rm -f "$LOCK_FILE"
    fi
fi

# Acquire lock
echo "$$|$(date +%s)" > "$LOCK_FILE"
echo "LOCK ACQUIRED"
exit 0
