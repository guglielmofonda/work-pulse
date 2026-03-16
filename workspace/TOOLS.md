# TOOLS.md - Local Notes

Skills define *how* tools work. This file is for *your* specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:
- Channel IDs and names
- Bot user IDs
- File paths specific to your environment
- API endpoint references
- Anything environment-specific

---

## Work Pulse Scripts

**Guard (run at START of every pulse):**
```bash
$WORKSPACE_PATH/scripts/work-pulse-guard.sh
```
Checks/acquires lock at `/tmp/<YOUR_BOT_NAME>-work-pulse.lock`. Returns "LOCK ACQUIRED" (proceed) or "LOCKED" (exit with PULSE_SKIP). Lock has 12-min staleness timeout.

**Unlock (run at END of every pulse):**
```bash
$WORKSPACE_PATH/scripts/work-pulse-unlock.sh
```
Releases the lock. Always run this, even on errors.

**State file:**
```
$PROJECT_PATH/work-state.json
```
Persists across all work cycles. Contains: mode, priorityQueue, activeSubAgents, completedToday, checkpoints, blockers, metrics. See AGENTS.md "Work Pulse System" section for full schema.

---

## Slack

**Mentions:** Use `<@USER_ID>` format, NOT plain names like `@Name`.
- Example: `<@U_EXAMPLE1>` to tag Alice
- Plain text `@Alice` won't notify anyone

**Your human's Slack ID:** `<YOUR_SLACK_ID>`
**Bot's Slack ID:** `$BOT_USER_ID`

**Test channel:** Use a dedicated test channel for any Slack testing, not production channels.

### Thread Context Workaround

**Bug:** Some agent platforms don't load thread context for thread sessions.

**When in a thread session:** Fetch context BEFORE responding:
```bash
$WORKSPACE_PATH/scripts/slack-thread-context.sh <channel_id> <thread_ts> [limit]
```

**How to detect thread session:** Session name contains `thread:TIMESTAMP`

**Direct API call (if script unavailable):**
```bash
curl -s "https://slack.com/api/conversations.replies?channel=CHANNEL&ts=THREAD_TS&limit=20" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" | \
  jq '.messages[] | {user, text: .text[0:300], ts}'
```

### Channels Bot Is In

| Channel | ID | requireMention | Notes |
|---------|-----|----------------|-------|
| #your-main-channel | <YOUR_CHANNEL_ID> | `false` | Main work channel |
| #your-test-channel | <YOUR_TEST_CHANNEL_ID> | `false` | Testing |
| #other-channel | <YOUR_OTHER_CHANNEL_ID> | `true` | Only see @mentions |

**Note:** For channels with `requireMention: true`, you only wake up when directly tagged. For `false`, you see all messages but follow AGENTS.md guidance on when to respond vs stay silent.

### Monitoring for Missed Messages

Safety net script to check for unanswered @mentions:
```bash
$WORKSPACE_PATH/scripts/slack-check-unanswered.sh
```

Returns any @mentions in the last 2 hours that might not have been answered. Run periodically or during heartbeats as a sanity check.

---

## Checkpoint Reports

**BEFORE sending a checkpoint:**
1. Read `state/checkpoint-state.json`
2. Check if 15+ minutes have passed since `lastCheckpoint.timestamp`
3. If not, DO NOT SEND — batch the update into the next checkpoint
4. After sending, UPDATE the file with current timestamp

**State file:** `$WORKSPACE_PATH/state/checkpoint-state.json`

**Format:**
```
[Time] Checkpoint
ROLLING: no blockers  /  BLOCKED: [specific thing]

[Deliverable] -- [STATUS] -- [GitHub link]
  Action needed: [who does what]
```

**Timing:**
- 15-30 min intervals (15 if blockers/urgent, 30 if rolling smooth)
- Continue working as sub-agents complete — don't wait for arbitrary intervals

**Status tags:**
- `[READY TO DEPLOY]` — just needs someone to merge/deploy
- `[NEEDS REVIEW]` — want human's eyes before it goes live
- `[WIP]` — still working

**Always include:** GitHub links to all work produced

---

## Custom Tools

Add your own tool notes below. Examples:

```markdown
### TTS
- Preferred voice: "Nova"
- Default speaker: Kitchen HomePod

### Browser Automation
- Use headless browser first for form filling & OAuth flows
- Use Chrome relay as fallback for existing logged-in sessions

### Integrations
- Whoop: $WORKSPACE_PATH/integrations/whoop/get-calories.sh
- Gmail: $WORKSPACE_PATH/integrations/gmail/gmail.sh
```

---

Add whatever helps you do your job. This is your cheat sheet.
