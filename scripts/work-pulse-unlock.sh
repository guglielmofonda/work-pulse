#!/bin/bash
# work-pulse-unlock.sh
# Releases the work pulse lock. Run at the end of every work cycle.

LOCK_FILE="/tmp/ercole-work-pulse.lock"
rm -f "$LOCK_FILE"
echo "LOCK RELEASED"
