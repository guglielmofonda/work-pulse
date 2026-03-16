#!/bin/bash
# Sync a Slack channel's history to a markdown file in a git repo.
#
# Required environment variables:
#   SLACK_BOT_TOKEN   - Slack Bot User OAuth Token (xoxb-...)
#   SLACK_CHANNEL_ID  - Channel ID to sync (e.g., C0XXXXXXXXXX)
#   PROJECT_REPO_PATH - Local path to the git repo where the log is stored
#
# Optional:
#   SLACK_CHANNEL_NAME - Human-readable channel name (default: "project-channel")
#   MESSAGE_LIMIT      - Number of messages to fetch (default: 150)

set -eo pipefail

# --- Configuration (from environment) ---
BOT_TOKEN="${SLACK_BOT_TOKEN:?Error: SLACK_BOT_TOKEN is not set}"
CHANNEL="${SLACK_CHANNEL_ID:?Error: SLACK_CHANNEL_ID is not set}"
REPO_PATH="${PROJECT_REPO_PATH:?Error: PROJECT_REPO_PATH is not set}"
CHANNEL_NAME="${SLACK_CHANNEL_NAME:-project-channel}"
LIMIT="${MESSAGE_LIMIT:-150}"

# --- Setup ---
cd "$REPO_PATH"
git pull --quiet 2>/dev/null || true
mkdir -p context

# --- Fetch and process with Python ---
curl -s "https://slack.com/api/conversations.history?channel=${CHANNEL}&limit=${LIMIT}" \
  -H "Authorization: Bearer ${BOT_TOKEN}" | python3 -c "
import json, sys
from datetime import datetime

history = json.load(sys.stdin)

# Map Slack user IDs to display names.
# Customize this for your workspace.
users = {
    'U_EXAMPLE1': 'Alice',
    'U_EXAMPLE2': 'Bob',
    'U_BOT':      'Agent'
}

def replace_mentions(text):
    for uid, name in users.items():
        text = text.replace(f'<@{uid}>', f'@{name}')
    return text

channel_name = '${CHANNEL_NAME}'

output = f'''# #{channel_name} Channel Log

*Auto-synced channel history for project context.*

**Last updated:** {datetime.now().strftime('%Y-%m-%d %H:%M')}

---

'''

messages = history.get('messages', [])
messages.reverse()

for msg in messages:
    text = msg.get('text', '')
    if not text or 'has joined the channel' in text:
        continue
    dt = datetime.fromtimestamp(float(msg.get('ts', 0)))
    user = users.get(msg.get('user', ''), msg.get('user', 'bot'))
    text = replace_mentions(text)
    reply_count = msg.get('reply_count', 0)
    output += f'### [{dt.strftime(\"%Y-%m-%d %H:%M\")}] {user}\n\n{text}\n'
    if reply_count > 0:
        output += f'\n*({reply_count} replies in thread)*\n'
    output += '\n---\n\n'

with open('context/slack-channel-log.md', 'w') as f:
    f.write(output)
"

# --- Commit if changed ---
if ! git diff --quiet context/slack-channel-log.md 2>/dev/null; then
  git add context/slack-channel-log.md
  git commit -m "Sync #${CHANNEL_NAME} channel log $(date '+%Y-%m-%d %H:%M')"
  git push --quiet
  echo "Channel log synced and pushed"
else
  echo "No changes to sync"
fi
