# Scaling Guide

Work Pulse ships with sensible defaults: 15-minute intervals, one project, Slack as the communication channel, weekday business hours. This guide covers how to change each of those.

## Changing the Interval

The default 15-minute interval works well for active projects where you want tight feedback loops. For steadier work or lower token budgets, longer intervals make sense.

### 30-Minute Pulses

Change the work pulse cron expression from:

```
5,20,35,50 9-16 * * 1-5
```

to:

```
5,35 9-16 * * 1-5
```

This fires at :05 and :35 past each hour. You'll get roughly 16 pulses per day instead of 32.

Update the guard script's staleness threshold to match:

```bash
MAX_AGE_SECONDS=1440  # 24 minutes (80% of 30-min interval)
```

### Hourly Pulses

```
5 9-16 * * 1-5
```

Fires at :05 past each hour. About 8 pulses per day. Good for projects where sub-agents run long tasks and there's rarely something new to harvest at 15-minute granularity.

Guard threshold:

```bash
MAX_AGE_SECONDS=2880  # 48 minutes (80% of 60-min interval)
```

### Custom Intervals

The general formula:
- **Cron expression**: Choose your minutes within the hour and your hour range
- **Guard staleness**: Set `MAX_AGE_SECONDS` to 80% of your interval in seconds
- **Morning and EOD**: These stay on fixed times regardless of pulse interval

For a 10-minute interval (aggressive, high-frequency):

```
0,10,20,30,40,50 9-16 * * 1-5
```

```bash
MAX_AGE_SECONDS=480  # 8 minutes
```

Note: shorter intervals mean more orchestration tokens per day. At 10-minute intervals, you're running ~48 pulses per day, which adds up. Only use this if the project genuinely benefits from tighter feedback loops.

## Adding a QA Sub-agent

The included `skills/qa-agent/SKILL.md` defines a quality review skill. To integrate it into the pulse cycle, add a QA spawn step between harvest and checkpoint.

### When to QA

Not every pulse needs QA. A practical pattern:

- **Always QA** deliverables that will be shared externally (client reports, deployed code, public docs)
- **Skip QA** for internal work products, exploration, and intermediate outputs
- **QA on demand** when the human requests a review

### Integration Pattern

In the assess step (step 5), when a sub-agent has completed a significant deliverable:

1. Before marking the task as `done`, mark it as `in-review`
2. Spawn a QA sub-agent with the deliverable and the original task description
3. In the next pulse, harvest the QA result
4. If verdict is SHIP: mark task as `done`, include in checkpoint
5. If verdict is REVISE: spawn a revision sub-agent with the QA feedback, keep task as `in-progress`
6. If verdict is REDO: spawn a fresh sub-agent with the QA feedback, keep task as `in-progress`

This adds one pulse of latency to deliverables (they complete in pulse N, get QA'd in pulse N+1, ship in pulse N+2) but catches quality issues before they reach humans.

### Token Cost

QA reviews are lightweight. The QA sub-agent reads the deliverable and the original ask, evaluates against 5 dimensions, and returns a structured verdict. Typical cost is 3,000-5,000 tokens per review, much cheaper than the work that produced the deliverable.

## Running Multiple Projects

Each project needs its own state and its own cron schedule. The key is preventing cross-contamination: different lock files, different state files, different Slack channels (or at minimum, different thread prefixes).

### Setup for Two Projects

**Project A** (main product work):

```
# Cron jobs for Project A
0 9 * * 1-5      morning-kickoff-project-a
5,20,35,50 9-16 * * 1-5   pulse-project-a
0 17 * * 1-5      eod-project-a
```

```json
{
  "guard": {
    "lockFile": "/tmp/work-pulse-project-a.lock"
  }
}
```

Environment:
```bash
export PROJECT_PATH="<YOUR_PROJECT_A_PATH>"
export SLACK_CHANNEL_ID="$SLACK_CHANNEL_ID_PROJECT_A"
```

**Project B** (side project):

```
# Cron jobs for Project B -- offset by 7 minutes to avoid collision
7 9 * * 1-5      morning-kickoff-project-b
7,22,37,52 9-16 * * 1-5   pulse-project-b
7 17 * * 1-5      eod-project-b
```

```json
{
  "guard": {
    "lockFile": "/tmp/work-pulse-project-b.lock"
  }
}
```

Environment:
```bash
export PROJECT_PATH="<YOUR_PROJECT_B_PATH>"
export SLACK_CHANNEL_ID="$SLACK_CHANNEL_ID_PROJECT_B"
```

### Why Offset the Schedules?

If both projects fire at the same minute, the agent platform may struggle to run two full agent sessions concurrently. Offsetting by a few minutes ensures they don't compete for resources. The offset doesn't need to be large -- 5-10 minutes is plenty.

### Shared vs. Separate Channels

**Separate Slack channels** (recommended): each project posts to its own channel. Clean separation, easy to mute one without losing the other.

**Shared channel with prefixes**: both projects post to the same channel, but prefix messages with `[Project A]` or `[Project B]`. Simpler setup, noisier channel. Works if you only have 2 projects and want a unified view.

## Adding Communication Channels

Slack is the default, but the checkpoint step can post anywhere that has an API.

### Adding Email Summaries

Instead of (or in addition to) Slack checkpoints, send an email digest. This works best at lower frequencies -- a per-pulse email would be noisy.

Pattern:
- Keep per-pulse checkpoints in Slack (or skip them entirely)
- Add an email step to the EOD cron job that compiles `completedToday`, `blockers`, and `metrics` into a summary email
- Use your platform's email integration or a tool call to a mail API

### Adding GitHub Issue Updates

If tasks map to GitHub issues, the checkpoint step can post progress comments:

- When a task moves to `in-progress`, post "Work started on this issue"
- When a task completes, post the output summary and link to the commit
- When a task is blocked, post the blocker description

This gives stakeholders who live in GitHub (rather than Slack) visibility into progress without requiring them to monitor a Slack channel.

### Webhook Integration

For maximum flexibility, add a webhook call at the end of each pulse that POSTs the current `work-state.json` to an endpoint of your choice. A downstream system can then route updates to any channel: dashboards, mobile notifications, database records, or other agent systems.

## Adjusting Work Hours and Timezones

### Changing Work Hours

The default schedule runs 9 AM to 5 PM. To change this, modify the hour range in all three cron expressions.

**Early schedule (7 AM -- 3 PM)**:
```
0 7 * * 1-5          morning kickoff
5,20,35,50 7-14 * * 1-5   pulses
0 15 * * 1-5          end of day
```

**Extended schedule (8 AM -- 8 PM)**:
```
0 8 * * 1-5          morning kickoff
5,20,35,50 8-19 * * 1-5   pulses
0 20 * * 1-5          end of day
```

**Split schedule (work mornings and evenings, skip afternoons)**:
```
0 8 * * 1-5          morning kickoff
5,20,35,50 8-11 * * 1-5   morning pulses
5,20,35,50 17-20 * * 1-5  evening pulses
0 21 * * 1-5          end of day
```

### Timezone Considerations

Cron jobs run in the timezone configured on the agent platform. If your platform uses UTC but you want pulses during US Pacific business hours (9 AM -- 5 PM PT = 5 PM -- 1 AM UTC the next day):

```
0 17 * * 1-5          morning kickoff (9 AM PT = 5 PM UTC)
5,20,35,50 17-23 * * 1-5  pulses (9 AM - 4 PM PT)
5,20,35,50 0 * * 2-6      pulses (4 PM - 5 PM PT = midnight UTC, shifts to next day)
0 1 * * 2-6           end of day (5 PM PT = 1 AM UTC next day)
```

This gets awkward with UTC offsets that cross midnight. If your platform supports timezone-aware cron (e.g., `CRON_TZ=America/Los_Angeles`), use that instead:

```
CRON_TZ=America/Los_Angeles
0 9 * * 1-5
5,20,35,50 9-16 * * 1-5
0 17 * * 1-5
```

### Weekend Work

To include weekends, change `1-5` (Monday-Friday) to `*` (every day):

```
5,20,35,50 9-16 * * *
```

Or specific days. For Monday through Saturday:

```
5,20,35,50 9-16 * * 1-6
```

The agent doesn't care what day it is. The state machine handles multi-day gaps gracefully (the morning kickoff resets cycle-specific fields when `today` doesn't match the current date), so adding or removing days is purely a cron configuration change.
