#!/bin/bash
# Setup script for Work Pulse cron jobs
#
# Prerequisites:
#   - openclaw CLI installed and authenticated
#   - openclaw gateway running
#   - Prompt files exist in ./prompts/ directory
#
# This script creates three cron jobs that form the Work Pulse system:
#   1. Morning Kickoff  - Runs at 9:00am weekdays
#   2. Work Pulse       - Runs every 15 min (9:05am-4:50pm weekdays)
#   3. End of Day       - Runs at 5:00pm weekdays
#
# Usage:
#   1. Edit the Configuration section below
#   2. Run: bash setup/openclaw-setup.sh
#   3. Verify with: openclaw cron list

set -euo pipefail

# ============================================================
# Configuration — edit these to match your environment
# ============================================================

WORKSPACE_PATH="${WORKSPACE_PATH:-$HOME/workspace}"
PROJECT_PATH="${PROJECT_PATH:-$HOME/project}"
SLACK_CHANNEL_ID="${SLACK_CHANNEL_ID:-C_YOUR_CHANNEL}"
BOT_NAME="${BOT_NAME:-Agent}"
TIMEZONE="${TIMEZONE:-America/Los_Angeles}"

# ============================================================
# Validate
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v openclaw &>/dev/null; then
  echo "Error: openclaw CLI not found. Install it first."
  exit 1
fi

for f in prompts/morning-kickoff.md prompts/work-pulse.md prompts/end-of-day.md; do
  if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
    echo "Error: Missing prompt file: $SCRIPT_DIR/$f"
    exit 1
  fi
done

echo "Setting up Work Pulse cron jobs..."
echo "  Workspace: $WORKSPACE_PATH"
echo "  Project:   $PROJECT_PATH"
echo "  Channel:   $SLACK_CHANNEL_ID"
echo "  Bot name:  $BOT_NAME"
echo "  Timezone:  $TIMEZONE"
echo ""

# ============================================================
# Helper: Extract prompt text from markdown code block
# ============================================================
# The prompt files contain the actual prompt inside a code block.
# This function extracts text between the first ``` and the next ```.

extract_prompt() {
  local file="$1"
  sed -n '/^```$/,/^```$/{/^```$/d;p}' "$file"
}

# ============================================================
# Substitute placeholders in prompt text
# ============================================================

substitute_vars() {
  local text="$1"
  echo "$text" \
    | sed "s|\\\$WORKSPACE_PATH|$WORKSPACE_PATH|g" \
    | sed "s|\\\$PROJECT_PATH|$PROJECT_PATH|g" \
    | sed "s|<YOUR_CHANNEL_ID>|$SLACK_CHANNEL_ID|g" \
    | sed "s|<YOUR_BOT_NAME>|$BOT_NAME|g"
}

# ============================================================
# Create Morning Kickoff
# ============================================================

echo "Creating: Work Cycle - Morning Kickoff..."

MORNING_PROMPT=$(extract_prompt "$SCRIPT_DIR/prompts/morning-kickoff.md")
MORNING_PROMPT=$(substitute_vars "$MORNING_PROMPT")

openclaw cron add \
  --name "Work Cycle - Morning Kickoff" \
  --session isolated \
  --wake next-heartbeat \
  --cron "0 9 * * 1-5" \
  --tz "$TIMEZONE" \
  --message "$MORNING_PROMPT" \
  --timeout-seconds 300

echo "  Done."

# ============================================================
# Create Work Pulse (every 15 min during work hours)
# ============================================================

echo "Creating: Work Cycle - Pulse..."

PULSE_PROMPT=$(extract_prompt "$SCRIPT_DIR/prompts/work-pulse.md")
PULSE_PROMPT=$(substitute_vars "$PULSE_PROMPT")

openclaw cron add \
  --name "Work Cycle - Pulse" \
  --session isolated \
  --wake next-heartbeat \
  --cron "5,20,35,50 9-16 * * 1-5" \
  --tz "$TIMEZONE" \
  --message "$PULSE_PROMPT" \
  --timeout-seconds 600

echo "  Done."

# ============================================================
# Create End of Day
# ============================================================

echo "Creating: Work Cycle - End of Day..."

EOD_PROMPT=$(extract_prompt "$SCRIPT_DIR/prompts/end-of-day.md")
EOD_PROMPT=$(substitute_vars "$EOD_PROMPT")

openclaw cron add \
  --name "Work Cycle - End of Day" \
  --session isolated \
  --wake next-heartbeat \
  --cron "0 17 * * 1-5" \
  --tz "$TIMEZONE" \
  --message "$EOD_PROMPT" \
  --timeout-seconds 300

echo "  Done."

# ============================================================
# Summary
# ============================================================

echo ""
echo "All 3 cron jobs created successfully."
echo ""
echo "Verify with:"
echo "  openclaw cron list"
echo ""
echo "To disable a job:"
echo "  openclaw cron disable <job-id>"
echo ""
echo "NOTE: Make sure the following scripts exist before the first pulse:"
echo "  $WORKSPACE_PATH/scripts/work-pulse-guard.sh"
echo "  $WORKSPACE_PATH/scripts/work-pulse-unlock.sh"
echo "  $WORKSPACE_PATH/scripts/slack-sync-channel.sh"
echo "  $WORKSPACE_PATH/scripts/slack-check-unanswered.sh"
