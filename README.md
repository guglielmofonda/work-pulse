# Work Pulse

Autonomous work cycles for AI agents. Cron handles time. Agents handle thinking.

## The Problem

Large language models have no sense of time. They process prompts and produce responses, but between those events, nothing happens. There is no persistent process ticking away, no background thread counting seconds. When a session ends, the agent ceases to exist until the next request arrives.

This creates a fundamental mismatch when you want an AI agent to work autonomously throughout a day. You might tell it: "Work on these tasks and post an update every 15 minutes." The agent will dutifully spawn sub-agents, wait for them to return, and report back. But that report arrives 3 minutes later, not 15 -- because the sub-agents finished quickly, and the agent has no way to distinguish "I completed a batch of work" from "15 minutes have passed." It conflates throughput with duration.

The result is chaos. The agent posts a "15-minute update" every 2-3 minutes. Your Slack channel fills with noise. The agent burns tokens re-checking things it just checked. If you add instructions like "wait longer between updates," the agent either ignores them (no mechanism to wait) or hallucinates compliance (says it waited when it didn't). The core issue isn't a prompting problem. It's an architecture problem: you're asking a stateless function to behave like a long-running process.

## The Solution

Separate time management from work management. Don't ask the agent to track time -- it can't. Instead, use an external scheduler (cron) as the clock and let the agent focus on what it's good at: reading context, making decisions, and doing work.

The key insight is that each work cycle should be a **pure function**. The agent wakes up, reads its state from a file, does a bounded unit of work, writes the updated state back, and exits. It has no concept of "how long until the next cycle" -- that's cron's job. The agent doesn't loop, doesn't wait, doesn't poll. It fires, works, and dies.

This turns an impossible problem (make a stateless LLM act like a daemon) into a solved one (run a stateless function on a schedule). Cron has been doing this reliably since 1975.

## Architecture

```
CRON SCHEDULE (external clock)             AGENT (pure function)
================================           ====================================
09:00  Morning Kickoff  ──────────►        Read goals → Plan day → Spawn → Post standup
09:05  Pulse #1         ──────────►        Harvest → Assess → Spawn → Checkpoint
09:20  Pulse #2         ──────────►        Harvest → Assess → Spawn → Checkpoint
09:35  Pulse #3         ──────────►        Harvest → Assess → Spawn → Checkpoint
...                     ──────────►        (same cycle, every 15 min)
16:50  Pulse #31        ──────────►        Final work cycle
17:00  End-of-Day       ──────────►        Summarize → Report → Shut down
```

Three cron jobs drive the entire system:

| Job              | Schedule                    | What It Does                                    |
|------------------|-----------------------------|-------------------------------------------------|
| Morning Kickoff  | `0 9 * * 1-5`              | Read GOALS.md and TASKS.md, plan the day, spawn first sub-agents, post standup to Slack |
| Work Pulse       | `5,20,35,50 9-16 * * 1-5`  | Harvest sub-agent results, assess progress, spawn new work, post checkpoint             |
| End-of-Day       | `0 17 * * 1-5`             | Summarize what shipped, report blockers, write final state, shut down                   |

Everything between pulses happens externally -- sub-agents run, humans respond in Slack, files get committed. The agent doesn't need to be alive for any of it.

## How a Pulse Works

Every pulse follows the same 8-step sequence:

1. **Guard** -- Run `work-pulse-guard.sh` to acquire a lock file at `/tmp/work-pulse.lock`. If another pulse is already running (lock exists and is less than 12 minutes old), skip this cycle entirely. This prevents overlapping pulses from corrupting state.

2. **Read state** -- Load `work-state.json`. This single file contains everything the agent needs: today's plan, active sub-agents, completed work, blockers, metrics, and the human input queue. The agent has no memory beyond this file.

3. **Check Slack** -- Read the project channel for any new messages from humans since the last pulse. Humans might have changed priorities, unblocked something, or asked a question. This input goes into `humanInputQueue` for processing.

4. **Harvest** -- Check on active sub-agents via `sessions_list`. For any that have completed, read their output via `sessions_history`. Record results in `completedThisCycle`. For any that failed, log them and decide whether to retry.

5. **Assess** -- Look at the priority queue, completed work, and blockers. What's the highest-priority unblocked task? Are there tasks that can run in parallel? Has a human unblocked something? This is where the agent's judgment matters most.

6. **Spawn** -- Delegate work to sub-agents (up to N active at once, typically 2-3). Each sub-agent gets a focused task, relevant context, and clear success criteria. Track them in `activeSubAgents` with labels for harvesting next pulse.

7. **Checkpoint** -- Post a structured update to Slack. Main message is a scannable status line. Thread reply #1 covers anything that needs human input. Thread reply #2 has technical details for anyone who wants depth. This 3-layer pattern keeps the channel clean while preserving detail.

8. **Update and unlock** -- Write the updated `work-state.json`, increment `cycleNumber`, update `lastPulseAt`, and release the lock. The agent's job is done. It exits. Cron will wake it again in 15 minutes.

## Results

First full day running Work Pulse on a real project:

- **7 cycles** completed (morning + 6 pulses before manual stop)
- **5 deliverables** shipped to the repo with commits
- **6 checkpoints** posted at regular ~15-minute intervals
- **0 Slack spam** (compared to constant rapid-fire updates before)
- **1 failed sub-agent** automatically detected and retried
- **1 blocker** surfaced clearly for human action

The difference wasn't incremental. Before Work Pulse, the agent would flood Slack with "updates" every 2-3 minutes, each one indistinguishable from the last. After, updates arrived on a predictable cadence with clear structure. The human could glance at Slack once every 30 minutes and understand exactly what was happening.

## Getting Started

### Prerequisites

- [OpenClaw](https://openclaw.ai) (or any agent platform that supports cron scheduling and sub-agent spawning)
- A Slack workspace with a bot token that can post to channels and read messages
- A project repository with `GOALS.md` and `TASKS.md` defining what the agent should work on

### Quick Setup

1. Copy `workspace/` files to your agent's workspace directory:
   ```bash
   cp workspace/SOUL.md workspace/HEARTBEAT.md <YOUR_WORKSPACE_PATH>/
   ```

2. Copy `scripts/` to your scripts directory:
   ```bash
   cp scripts/work-pulse-guard.sh scripts/work-pulse-unlock.sh <YOUR_SCRIPTS_PATH>/
   chmod +x <YOUR_SCRIPTS_PATH>/work-pulse-*.sh
   ```

3. Copy the initial state file to your project:
   ```bash
   cp state/work-state.initial.json <YOUR_PROJECT_PATH>/work-state.json
   ```

4. Set up environment variables (see below).

5. Create the three cron jobs on your agent platform:
   - **Morning Kickoff**: `0 9 * * 1-5` -- triggers the morning planning prompt
   - **Work Pulse**: `5,20,35,50 9-16 * * 1-5` -- triggers the pulse prompt
   - **End-of-Day**: `0 17 * * 1-5` -- triggers the EOD summary prompt

6. Wait for 9:00 AM on the next weekday, or trigger the morning kickoff manually to test.

### Environment Variables

| Variable           | Description                                      |
|--------------------|--------------------------------------------------|
| `SLACK_BOT_TOKEN`  | Bot token with `chat:write` and `channels:history` scopes |
| `SLACK_CHANNEL_ID` | Channel ID for posting checkpoints               |
| `BOT_USER_ID`      | The bot's Slack user ID (for filtering its own messages) |
| `PROJECT_PATH`     | Absolute path to the project repository           |
| `WORKSPACE_PATH`   | Absolute path to the agent's workspace directory  |

Set these in your agent platform's environment configuration, not in code:

```bash
export SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN"
export SLACK_CHANNEL_ID="$SLACK_CHANNEL_ID"
export BOT_USER_ID="$BOT_USER_ID"
export PROJECT_PATH="<YOUR_PROJECT_PATH>"
export WORKSPACE_PATH="<YOUR_WORKSPACE_PATH>"
```

## Customization

**Change the interval.** The default is every 15 minutes. For longer cycles, edit the cron expression. For 30-minute pulses: `5,35 9-16 * * 1-5`. For hourly: `5 9-16 * * 1-5`. Adjust the guard's `MAX_AGE_SECONDS` accordingly (it should be ~80% of your interval).

**Add QA review.** Use the included `skills/qa-agent/` skill to spawn a QA sub-agent before each checkpoint. The QA agent reviews work products against 5 dimensions (completeness, rigor, accuracy, actionability, quality) and returns a SHIP/REVISE/REDO verdict.

**Run multiple projects.** Each project gets its own `work-state.json` and its own set of cron jobs. Use different `PROJECT_PATH` values and separate lock files (change the path in `guard.lockFile`) to prevent cross-project interference.

**Change work hours.** The `9-16` range in cron expressions maps to 9 AM -- 4:50 PM. Adjust for your timezone or preferred hours. For a 7 AM -- 3 PM schedule: `5,20,35,50 7-14 * * 1-5`.

## File Structure

```
work-pulse/
├── README.md                          # This file
├── docs/
│   ├── why-llms-cant-track-time.md    # The core insight behind the system
│   ├── architecture.md                # Full technical deep dive
│   └── scaling.md                     # Customization and scaling guide
├── workspace/
│   ├── SOUL.md                        # Agent identity and principles
│   └── HEARTBEAT.md                   # Periodic check definitions
├── scripts/
│   ├── work-pulse-guard.sh            # Lock acquisition (run at pulse start)
│   └── work-pulse-unlock.sh           # Lock release (run at pulse end)
├── state/
│   ├── work-state.initial.json        # Clean starting state (copy to project)
│   └── work-state.example.json        # Example state after a full day of work
├── skills/
│   └── qa-agent/
│       └── SKILL.md                   # QA review skill for sub-agent spawning
└── prompts/                           # (Add your cron-triggered prompts here)
```

## Learn More

- [Why LLMs Can't Track Time](docs/why-llms-cant-track-time.md) -- the core insight that motivated the entire system
- [Architecture Deep Dive](docs/architecture.md) -- full technical walkthrough of state, guards, spawning, and checkpoints
- [Scaling Guide](docs/scaling.md) -- from 15-minute to 30-minute intervals, multi-project setups, and beyond

## License

MIT
