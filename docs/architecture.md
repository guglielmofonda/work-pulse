# Architecture Deep Dive

This document covers the full technical design of Work Pulse: how state flows through the system, how guards prevent corruption, how sub-agents are managed, and how edge cases are handled.

## State Machine Lifecycle

The agent operates as a state machine with five modes. The `mode` field in `work-state.json` determines what the agent does when it wakes up.

```
                       ┌──────────────────────────────────┐
                       │                                  │
                       v                                  │
  ┌──────────┐    ┌─────────┐    ┌─────────┐    ┌────────────────┐
  │ day-     │───►│ morning │───►│ working │───►│ day-complete   │
  │ complete │    │         │    │         │    │                │
  └──────────┘    └─────────┘    └─────────┘    └────────────────┘
       ▲                              │  ▲
       │                              │  │
       │                              v  │
       │                         ┌─────────┐
       │                         │ blocked  │
       │                         └─────────┘
       │                              │
       │                              v
       │                    ┌───────────────────┐
       └────────────────────│ waiting-for-human │
                            └───────────────────┘
```

**day-complete** -- The resting state. The agent has finished its day or hasn't started yet. When the morning kickoff cron fires, it transitions to `morning`.

**morning** -- The agent reads `GOALS.md` and `TASKS.md`, builds a priority queue for the day, spawns initial sub-agents, posts a standup message to Slack, and transitions to `working`.

**working** -- The main operating mode. Every pulse reads state, harvests sub-agents, assesses priorities, spawns new work, and posts a checkpoint. Stays in `working` until end-of-day or until all tasks are blocked.

**blocked** -- All tasks in the priority queue are blocked on external dependencies (human input, access grants, third-party responses). The agent posts a blocker summary instead of a normal checkpoint. Transitions back to `working` when the Slack sync step detects a human has unblocked something.

**waiting-for-human** -- A special case of blocked where the agent has explicitly asked a human a question and cannot proceed without an answer. Unlike `blocked`, this mode suppresses spawning entirely to avoid wasting compute on work that might be redirected.

**day-complete** (again) -- The EOD cron triggers a summary. The agent writes a final report, resets cycle-specific fields, and enters `day-complete` for the night.

## The Guard Pattern

Cron fires on a fixed schedule, but the agent's work takes variable time. A pulse might finish in 3 minutes or take 11. If a pulse runs long and overlaps with the next scheduled pulse, two agents could read and write the same state file simultaneously, corrupting it.

The guard prevents this with a lock file.

### How It Works

```bash
LOCK_FILE="/tmp/work-pulse.lock"
MAX_AGE_SECONDS=720  # 12 minutes
```

When a pulse starts, it runs `work-pulse-guard.sh`:

1. **Check if lock exists.** If no lock file, acquire it and proceed.
2. **If lock exists, check age.** If the lock is less than 12 minutes old, another pulse is legitimately running. Exit with code 1 (skip this cycle).
3. **If lock is stale (>12 min),** remove it. A pulse should never take 12 minutes. If the lock is that old, the previous pulse crashed or hung. Remove the stale lock and acquire a fresh one.
4. **Acquire lock.** Write the process ID and timestamp to the lock file.

When the pulse finishes (step 8), `work-pulse-unlock.sh` removes the lock file.

### Why 12 Minutes?

The pulse interval is 15 minutes. If a pulse is still running after 12 minutes, something is wrong -- and the next pulse is about to fire in 3 minutes. The 12-minute threshold gives a 3-minute buffer: enough time for the guard to detect the stale lock, remove it, and start fresh, all before the next pulse arrives.

If you change the interval (say, to 30 minutes), adjust `MAX_AGE_SECONDS` to roughly 80% of the new interval (24 minutes = 1440 seconds).

### What the Lock Prevents

Without the guard, here's what could happen:

```
09:20:00  Pulse #2 starts, reads work-state.json (sub-agent A is active)
09:20:05  Pulse #2 harvests sub-agent A (completed), writes "A: done" to state
09:20:00  Pulse #3 starts (overlap!), reads work-state.json (sub-agent A is active)
09:20:06  Pulse #2 spawns sub-agent B, writes "B: active" to state
09:20:07  Pulse #3 harvests sub-agent A (completed), writes "A: done" to state
          ^^^ Pulse #3's write OVERWRITES Pulse #2's state, losing sub-agent B
```

The guard makes this impossible. Pulse #3 sees the lock, skips, and waits for the next cycle.

## work-state.json Deep Dive

The state file is the single source of truth. Here's every field and its purpose:

```json
{
  "version": 2,
  "mode": "working",
  "today": "2026-03-16",
  "cycleNumber": 7,
  "lastPulseAt": "2026-03-16T10:20:00-07:00",
  "lastPulseType": "pulse",
  "guard": {
    "lockFile": "/tmp/work-pulse.lock"
  },
  "plan": {
    "createdAt": "2026-03-16T09:00:00-07:00",
    "todaysGoal": "Ship deployment guide + build MCP server MVP",
    "priorityQueue": [...]
  },
  "activeSubAgents": [...],
  "completedThisCycle": [...],
  "completedToday": [...],
  "failedToday": [...],
  "checkpoints": [...],
  "blockers": [...],
  "humanInputQueue": [...],
  "metrics": {
    "subAgentsSpawned": 7,
    "subAgentsCompleted": 5,
    "subAgentsFailed": 1,
    "deliverablesPushed": 5,
    "checkpointsPosted": 6
  }
}
```

### Field-by-Field

**version** -- Schema version. Allows future migrations without breaking existing state files. Read on startup; never written during a pulse.

**mode** -- Current lifecycle state (`morning`, `working`, `blocked`, `waiting-for-human`, `day-complete`). Read first, determines pulse behavior. Written at end of pulse if a transition occurred.

**today** -- ISO date string. The morning kickoff sets this. If a pulse reads a `today` value that doesn't match the current date, it knows the state is stale (carried over from a previous day) and triggers a reset.

**cycleNumber** -- Monotonically increasing counter. Morning kickoff sets it to 1. Each pulse increments it. Useful for debugging ("which cycle did this happen in?") and for the agent to gauge how much of the day has passed.

**lastPulseAt** -- ISO timestamp of the most recent pulse. Used for staleness detection and for generating "time since last pulse" in checkpoint messages.

**lastPulseType** -- Either `morning-standup`, `pulse`, or `eod-summary`. Lets the agent know what happened last -- useful if it needs to adjust behavior (e.g., the first pulse after morning should check if the plan was created correctly).

**guard.lockFile** -- Path to the lock file. Configurable per-project so multiple projects can run without interfering.

**plan.createdAt** -- When the morning plan was built. Informational.

**plan.todaysGoal** -- One-sentence summary of the day's focus. Set during morning kickoff, referenced in every checkpoint for context.

**plan.priorityQueue** -- Ordered array of tasks for the day. Each task has:
- `id` -- Stable identifier (e.g., `task-1`)
- `description` -- What needs to be done
- `status` -- One of `pending`, `in-progress`, `done`, `blocked`
- `priority` -- Numeric rank (1 = highest)
- `blockedOn` -- What's blocking it (null if not blocked)
- `dependsOn` -- ID of another task that must complete first (null if independent)
- `completedAt` -- Timestamp of completion (null if not done)
- `output` -- Description of what was produced (null if not done)

The agent reads the queue to decide what to spawn. It writes to it when tasks change status.

**activeSubAgents** -- Array of currently running sub-agents. Each entry has a `sessionId` (from the platform), a `label` (human-readable name), a `taskId` (which priority queue task it's working on), and a `spawnedAt` timestamp. Read during harvest to know what to check. Written during spawn to register new sub-agents. Cleared during harvest as sub-agents complete.

**completedThisCycle** -- Work completed during THIS pulse only. Reset at the start of each pulse. Used to build the checkpoint message. Prevents the agent from re-reporting old completions.

**completedToday** -- Cumulative log of everything completed today. Appended during each pulse. Read during EOD to build the summary. Never cleared during the day.

**failedToday** -- Sub-agents that failed, with reason and whether a retry was attempted. Used for EOD reporting and for the agent to detect patterns (if the same task keeps failing, maybe it needs a different approach).

**checkpoints** -- Array of all checkpoint messages posted today, with type and timestamp. Used to verify the agent is actually posting at the right intervals, and for the EOD summary to count total checkpoints.

**blockers** -- Active blockers that require human or external action. Each has an `id`, `description`, `since` (when it was first identified), and `owner` (who can unblock it). Read during assess to skip blocked tasks. Written when a new blocker is discovered. Removed when the Slack sync step detects it's been resolved.

**humanInputQueue** -- Specific questions or requests for humans. Surfaced in checkpoint thread replies so humans see them. Cleared when the human responds (detected during Slack sync).

**metrics** -- Running counters for the day. Incremented during each pulse. Read during EOD for the summary report.

## Sub-agent Spawning and Harvesting

Sub-agents are the agent's workforce. The orchestrator (the pulse agent) doesn't do detailed work itself -- it delegates to sub-agents and manages their lifecycle.

### Spawning

When the assess step identifies work to be done, the agent spawns a sub-agent:

```
sessions_spawn(
  agentId: "default",
  task: "<detailed task description with context>",
  label: "descriptive-label"
)
```

The platform returns a `sessionId`. The agent records it in `activeSubAgents`:

```json
{
  "sessionId": "<returned-session-id>",
  "label": "deployment-guide",
  "taskId": "task-1",
  "spawnedAt": "2026-03-16T09:00:30-07:00"
}
```

The agent typically caps active sub-agents at 2-3 to manage complexity. More than that and harvesting becomes unwieldy, context gets fragmented, and the risk of conflicting work increases.

### Harvesting

Each pulse checks on active sub-agents:

```
sessions_list()  →  returns status of all sessions
```

For each entry in `activeSubAgents`, the agent checks the returned list:
- **Completed**: read the output via `sessions_history(sessionId)`, extract the result, move from `activeSubAgents` to `completedThisCycle` and `completedToday`, update the corresponding task in `priorityQueue` to `done`.
- **Still running**: leave it in `activeSubAgents`. It'll be checked again next pulse.
- **Failed**: log in `failedToday` with the error reason. Decide whether to retry (typically yes for transient failures like timeouts, no for fundamental errors).

### The Spawn-Harvest Rhythm

This creates a natural rhythm across pulses:

```
Pulse 1:  Spawn A, Spawn B         → activeSubAgents: [A, B]
Pulse 2:  Harvest A (done), Spawn C → activeSubAgents: [B, C]
Pulse 3:  Harvest B (done), C still running → activeSubAgents: [C]
Pulse 4:  Harvest C (done), Spawn D, Spawn E → activeSubAgents: [D, E]
```

Work flows continuously without the agent needing to "wait" for anything. If nothing completed since the last pulse, the agent simply reports "sub-agents still running" and exits. No wasted work, no polling loops.

## Checkpoint Structure

Checkpoints are the agent's primary communication channel with humans. Every pulse posts one. The structure is intentionally layered to serve different audiences.

### Layer 1: Main Message (Scannable)

Posted directly to the channel. Designed to be read in 2 seconds.

```
Pulse #7 | 5 tasks done | 0 active | 1 blocked
```

Anyone scrolling through Slack can see at a glance: the system is working, here's the count, here's the status. If everything looks fine, they don't need to read more.

### Layer 2: Thread Reply #1 (Human Action Needed)

Posted as a thread reply to the main message. Only included if there's something a human needs to do.

```
Needs human input:
- Deployment access to production site (blocked since Mar 13, owner: Team lead)
```

This is the "action items" layer. If a human only reads one thing in the thread, this is what they should see.

### Layer 3: Thread Reply #2 (Technical Detail)

Posted as a second thread reply. Full technical detail for anyone who wants it.

```
Completed this cycle:
- api-server-build: API server MVP complete, 3 endpoints + 3 resources, 1,248 lines (commit d83b280)

Active sub-agents: none

Today's metrics:
- 7 sub-agents spawned, 5 completed, 1 failed
- 5 deliverables pushed
- 6 checkpoints posted

Next: Waiting for deployment access to ship accumulated work
```

### Why Three Layers?

Single-message updates either include too much detail (noisy channel) or too little (humans can't tell what's happening). The three-layer pattern solves this by progressive disclosure:

- Channel-level: "everything is fine" or "action needed" (2 seconds)
- Thread level 1: "here's what I need from you" (10 seconds)
- Thread level 2: "here's everything that happened" (60 seconds)

Humans self-select their depth. Most pulses, they'll only see Layer 1. When they need to engage, Layers 2 and 3 are right there in the thread.

## Incorporating Human Input

The agent doesn't operate in a vacuum. Humans can redirect it between pulses by posting in the Slack channel.

### The Slack Sync Step

At the start of each pulse (step 3), the agent reads recent channel messages since `lastPulseAt`. It filters out its own messages (using `$BOT_USER_ID`) and processes human messages:

- **Priority changes**: "Drop the API server, focus on the deployment guide" -- the agent reorders `priorityQueue`.
- **Unblocking**: "I've granted deployment access" -- the agent removes the blocker and moves blocked tasks back to `pending`.
- **New tasks**: "Also need a README for the API server" -- the agent adds to `priorityQueue`.
- **Questions answered**: "Use the staging environment, not production" -- the agent clears the item from `humanInputQueue` and incorporates the answer.

### The humanInputQueue Pattern

When the agent needs human input, it doesn't block and wait. It:

1. Adds the question to `humanInputQueue`
2. Includes it in the next checkpoint (Layer 2)
3. Continues working on non-blocked tasks
4. Checks for the answer at the start of each subsequent pulse

This is asynchronous by design. The agent never stops working just because one question is unanswered. It works around the gap, and integrates the answer whenever it arrives.

## Edge Cases

### Overlapping Pulses

**Scenario**: A pulse takes 14 minutes. The next pulse fires at minute 15.

**Handling**: The guard catches this. If the lock is fresh (<12 min), the new pulse skips. If it's stale (>12 min), the old pulse probably hung -- remove the lock and proceed. The 12-minute threshold is chosen to give a 3-minute buffer.

### Failed Sub-agents

**Scenario**: A sub-agent crashes or times out.

**Handling**: The harvest step detects the failure via `sessions_list`. The agent logs it in `failedToday` with the error reason. For transient failures (timeouts, rate limits), it sets `retrying: true` and spawns a replacement. For fundamental failures (invalid task, missing access), it marks the task as blocked and surfaces it in the checkpoint.

### Machine Offline Overnight

**Scenario**: The agent platform shuts down at 6 PM and restarts at 8 AM.

**Handling**: The `today` field in `work-state.json` handles this. When the morning kickoff runs, it checks `today` against the current date. If they don't match, it knows the state is from a previous day. It resets cycle-specific fields (`cycleNumber`, `completedThisCycle`, `completedToday`, `checkpoints`, `metrics`) while preserving persistent fields (`blockers`, `humanInputQueue`). Blockers carry over between days because they represent real-world dependencies that don't resolve just because a calendar page turned.

### Weekend Handling

**Scenario**: It's Saturday. No cron jobs fire.

**Handling**: The cron expressions use `1-5` for the day-of-week field, meaning Monday through Friday only. The state file sits untouched over the weekend. Monday morning's kickoff picks up right where Friday left off, with stale blockers still visible and the priority queue intact from the last EOD.

### All Tasks Blocked

**Scenario**: Every task in the priority queue depends on human action or external input.

**Handling**: The agent transitions to `blocked` mode. Instead of a normal checkpoint, it posts a blocker summary emphasizing what's needed. It doesn't spawn any sub-agents (nothing to work on). Each subsequent pulse still fires, syncs Slack for unblocking signals, and transitions back to `working` if something gets unblocked. This prevents wasted compute while keeping the agent responsive.

### Stale State From a Crash

**Scenario**: The agent crashes mid-pulse after writing partial state.

**Handling**: The lock file remains (since `work-pulse-unlock.sh` never ran). The next pulse sees a fresh lock and skips. The pulse after that (or the one that hits the 12-minute staleness threshold) removes the lock and starts fresh. The state file might be partially updated, but since each field is written independently and the file is valid JSON at rest, the agent can usually recover by re-assessing the priority queue. The worst case is a duplicated sub-agent spawn (the agent thinks a task is still pending when it's actually in-progress), which is inefficient but not catastrophic.

## Token Budget

Work Pulse is designed to be economical. Here's a rough breakdown for a typical day.

### Per-Pulse Cost

Each pulse involves:
- Reading `work-state.json` (~500 tokens input)
- Reading Slack messages (~200-500 tokens input, depends on activity)
- Agent reasoning and decision-making (~1,000-2,000 tokens output)
- Tool calls for harvesting, spawning, posting (~500-1,000 tokens combined)

**Estimated per-pulse**: ~2,000-4,000 tokens total

### Daily Cost (15-minute intervals)

- Morning kickoff: ~3,000-5,000 tokens (reads GOALS.md, TASKS.md, builds plan)
- ~32 pulses at ~3,000 tokens average: ~96,000 tokens
- EOD summary: ~3,000-5,000 tokens
- Sub-agent work: varies dramatically by project (this is where real work happens)

**Orchestration overhead**: ~100,000-110,000 tokens/day for the pulse system itself.

Sub-agent costs are separate and depend entirely on what work you're doing. A sub-agent building an API server might use 50,000 tokens. A sub-agent writing a one-page document might use 5,000.

### Cost Optimization

- **Skip empty pulses**: If no sub-agents are active, no human input arrived, and nothing changed, the pulse can post a minimal checkpoint and exit early, saving ~2,000 tokens per empty cycle.
- **Increase interval**: Moving from 15 to 30 minutes cuts orchestration overhead roughly in half.
- **Reduce checkpoint verbosity**: Layer 3 (technical details) can be skipped when nothing interesting happened.

The orchestration overhead is small compared to the work sub-agents do. On the test day that produced the example state file, sub-agent work consumed roughly 10x more tokens than the pulse system itself. The pulse system is the manager -- it's supposed to be lightweight.
