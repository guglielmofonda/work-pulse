# End of Day Prompt

This prompt runs once at the end of each workday (e.g., 5:00pm weekdays). It harvests any remaining work, updates task tracking, creates a daily log, commits everything, posts an EOD report to Slack, and shuts down the work cycle.

## Prompt

```
You are <YOUR_BOT_NAME>. This is your END-OF-DAY REPORT.

STEP 0: GUARD
Run: bash $WORKSPACE_PATH/scripts/work-pulse-guard.sh
If output contains "LOCKED", reply "PULSE_SKIP" and stop.

STEP 1: READ STATE
Read:
- $PROJECT_PATH/work-state.json
- $PROJECT_PATH/GOALS.md
- $PROJECT_PATH/TASKS.md

STEP 2: HARVEST REMAINING
Run sessions_list. Collect any final outputs from still-running sub-agents via sessions_history.
Update completedToday.

STEP 3: UPDATE TASKS
Mark completed items done in TASKS.md. Add new tasks discovered today.
Note blockers for tomorrow.

STEP 4: CREATE DAILY LOG
Write $PROJECT_PATH/daily-logs/<YYYY-MM-DD>.md with:
- Summary (2-3 lines)
- Work completed (from completedToday)
- Key findings
- Blockers for tomorrow
- Commits made
- Tomorrow's priorities

STEP 5: COMMIT & PUSH
cd $PROJECT_PATH && git add -A && git commit -m "Daily log: <date>" && git push

STEP 6: POST EOD REPORT
Send to Slack <YOUR_CHANNEL_ID>:

"End of Day — <date>

Goal: <todaysGoal>
Cycles: <cycleNumber>

Shipped:
- <item> — <link>
- <item> — <link>

Blocked:
- <blocker> — waiting on <who>

Tomorrow:
1. <priority>
2. <priority>
3. <priority>

Metrics: <N> agents spawned, <N> completed, <N> deliverables"

STEP 7: SHUTDOWN
Set mode to "day-complete" in work-state.json.
Run: bash $WORKSPACE_PATH/scripts/work-pulse-unlock.sh
```

## Customization

- Replace `$WORKSPACE_PATH` with your actual workspace path (e.g., `~/workspace`)
- Replace `$PROJECT_PATH` with your project repo path (e.g., `~/project`)
- Replace `<YOUR_BOT_NAME>` with your agent's name
- Replace `<YOUR_CHANNEL_ID>` with your Slack channel ID
- Adjust the daily log format to match your project's conventions
- The `sessions_list` and `sessions_history` commands assume your agent platform supports sub-agent introspection

## Cron Configuration

```
Schedule: 0 17 * * 1-5
Timezone: Your local timezone (e.g., America/Los_Angeles)
Session: isolated
Timeout: 300 seconds
```
