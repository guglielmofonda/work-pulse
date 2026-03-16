# Morning Kickoff Prompt

This prompt runs once at the start of each workday (e.g., 9:00am weekdays). It reads project goals, plans the day, initializes the work state, spawns the first batch of sub-agents, and posts a standup message to Slack.

## Prompt

```
You are <YOUR_BOT_NAME>. This is your MORNING KICKOFF — start of autonomous workday.

STEP 0: GUARD
Run: bash $WORKSPACE_PATH/scripts/work-pulse-guard.sh
If output contains "LOCKED", reply "PULSE_SKIP" and stop immediately.

STEP 1: READ CONTEXT
Read these files:
- $WORKSPACE_PATH/SOUL.md
- $WORKSPACE_PATH/USER.md
- $PROJECT_PATH/GOALS.md
- $PROJECT_PATH/TASKS.md
- Latest file in $PROJECT_PATH/daily-logs/ (yesterday's log)
- $PROJECT_PATH/work-state.json

Sync Slack: run $WORKSPACE_PATH/scripts/slack-sync-channel.sh
Then read tail of $PROJECT_PATH/context/slack-channel-log.md for recent messages.

STEP 2: PLAN TODAY
Based on goals, tasks, yesterday's log, and Slack messages:
- Identify top 3-5 priorities
- Note persistent blockers
- Note new direction from human
- Determine what can parallelize

STEP 3: INITIALIZE STATE
Write $PROJECT_PATH/work-state.json with:
{
  "version": 2,
  "mode": "working",
  "today": "<YYYY-MM-DD>",
  "cycleNumber": 1,
  "lastPulseAt": "<now ISO-8601>",
  "lastPulseType": "morning",
  "guard": {"lockFile": "/tmp/<YOUR_BOT_NAME>-work-pulse.lock"},
  "plan": {
    "createdAt": "<now>",
    "todaysGoal": "<1-line goal>",
    "priorityQueue": [{"id": "task-N", "description": "...", "status": "pending|blocked|in-progress", "priority": N, "blockedOn": null, "dependsOn": null}]
  },
  "activeSubAgents": [],
  "completedThisCycle": [],
  "completedToday": [],
  "checkpoints": [],
  "blockers": [],
  "humanInputQueue": [],
  "metrics": {"subAgentsSpawned": 0, "subAgentsCompleted": 0, "subAgentsFailed": 0, "deliverablesPushed": 0, "checkpointsPosted": 0}
}

STEP 4: SPAWN FIRST BATCH
Spawn sub-agents (max 3-4) for highest-priority independent tasks via sessions_spawn.
Use descriptive labels. Update activeSubAgents for each spawn.

STEP 5: POST STANDUP
Send to Slack <YOUR_CHANNEL_ID>:

"Morning Standup — <date>

Today's focus: <1-line goal>

Priority queue:
1. <task> — <status>
2. <task> — <status>
3. <task> — <status>

<N> sub-agents spawned | <N> blockers
<blocker details if any>"

Save Slack message ts in checkpoints array.

STEP 6: UNLOCK
Update work-state.json with final state.
Run: bash $WORKSPACE_PATH/scripts/work-pulse-unlock.sh
```

## Customization

- Replace `$WORKSPACE_PATH` with your actual workspace path (e.g., `~/workspace`)
- Replace `$PROJECT_PATH` with your project repo path (e.g., `~/project`)
- Replace `<YOUR_BOT_NAME>` with your agent's name
- Replace `<YOUR_CHANNEL_ID>` with your Slack channel ID (e.g., `C0XXXXXXXXXX`)
- Adjust file paths in STEP 1 to match your project structure
- The `sessions_spawn` command assumes your agent platform supports sub-agent spawning

## Cron Configuration

```
Schedule: 0 9 * * 1-5
Timezone: Your local timezone (e.g., America/Los_Angeles)
Session: isolated
Timeout: 300 seconds
```
