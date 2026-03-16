#!/bin/bash
# Check for unanswered @mentions in Slack channels.
#
# Returns ONLY NEW messages where bot was mentioned but not yet handled.
# Filters against a state file so cron doesn't waste tokens re-processing
# mentions that were already answered.
#
# Required environment variables:
#   SLACK_BOT_TOKEN  - Slack Bot User OAuth Token (xoxb-...)
#   BOT_USER_ID      - Your bot's Slack user ID (e.g., U0XXXXXXXXX)
#   WORKSPACE_PATH   - Path to your workspace root (for state file storage)
#
# Optional:
#   LOOKBACK_SECONDS - How far back to check (default: 7200 = 2 hours)
#   PRUNE_SECONDS    - How long to keep handled mentions (default: 86400 = 24 hours)

set -euo pipefail

# --- Configuration (from environment) ---
BOT_TOKEN="${SLACK_BOT_TOKEN:?Error: SLACK_BOT_TOKEN is not set}"
BOT_USER="${BOT_USER_ID:?Error: BOT_USER_ID is not set}"
WS_PATH="${WORKSPACE_PATH:?Error: WORKSPACE_PATH is not set}"
STATE_FILE="${WS_PATH}/state/slack-monitor-state.json"
LOOKBACK="${LOOKBACK_SECONDS:-7200}"
PRUNE_AGE="${PRUNE_SECONDS:-86400}"

# Channels to monitor.
# Format: "CHANNEL_ID"  # channel-name
# Add or remove channels as needed.
CHANNELS=(
  "<YOUR_CHANNEL_ID_1>"   # main-work-channel
  "<YOUR_CHANNEL_ID_2>"   # test-channel
  "<YOUR_CHANNEL_ID_3>"   # other-channel
)

# --- Time window ---
OLDEST=$(( $(date +%s) - LOOKBACK ))

# --- Ensure state file exists ---
mkdir -p "$(dirname "$STATE_FILE")"
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"handledMentions":{}}' > "$STATE_FILE"
fi

# --- Prune old entries and get handled list ---
CUTOFF=$(( $(date +%s) - PRUNE_AGE ))
HANDLED_TS=$(python3 << EOF
import json
from datetime import datetime

with open("$STATE_FILE", "r") as f:
    state = json.load(f)

cutoff = $CUTOFF
pruned = {}
handled_list = []

for ts, data in state.get("handledMentions", {}).items():
    handled_at = data.get("handledAt", "")
    try:
        dt = datetime.fromisoformat(handled_at.replace("Z", "+00:00"))
        if dt.timestamp() > cutoff:
            pruned[ts] = data
            handled_list.append(ts)
    except:
        pruned[ts] = data
        handled_list.append(ts)

state["handledMentions"] = pruned
with open("$STATE_FILE", "w") as f:
    json.dump(state, f, indent=2)

# Output space-separated list of handled timestamps
print(" ".join(handled_list))
EOF
)

# --- Check each channel for unhandled mentions ---
for CHANNEL in "${CHANNELS[@]}"; do
  # Get recent messages
  MESSAGES=$(curl -s "https://slack.com/api/conversations.history?channel=${CHANNEL}&oldest=${OLDEST}&limit=50" \
    -H "Authorization: Bearer ${BOT_TOKEN}" 2>/dev/null || echo '{"messages":[]}')

  # Find messages that mention the bot, exclude bot's own messages, filter out already-handled
  echo "$MESSAGES" | python3 -c "
import sys
import json

handled = set('$HANDLED_TS'.split())
bot_id = '$BOT_USER'
channel = '$CHANNEL'

try:
    data = json.load(sys.stdin)
    for msg in data.get('messages', []):
        ts = msg.get('ts', '')
        user = msg.get('user', '')
        text = msg.get('text', '')

        # Skip if already handled
        if ts in handled:
            continue

        # Skip bot's own messages
        if user == bot_id:
            continue

        # Check if bot is mentioned
        if f'<@{bot_id}>' not in text:
            continue

        # Output the mention
        print(f'Channel: {channel} | ts: {ts} | from: {user} | text: {text[:100]}')
except:
    pass
"
done
