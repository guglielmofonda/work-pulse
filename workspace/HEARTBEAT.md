# HEARTBEAT.md

## Periodic Checks (rotate through, don't do all every time)

### Slack Monitoring (every few hours)
Check for unanswered @mentions:
```bash
~/clawd/scripts/slack-check-unanswered.sh
```
If any found, respond to them.

# Keep checks minimal to limit token burn.
