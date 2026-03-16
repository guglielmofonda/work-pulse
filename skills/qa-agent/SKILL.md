# QA Agent Skill

## Purpose
Quality assurance review of work products before they're marked "ready". Acts as a skeptical second pair of eyes that assumes work is incomplete until proven otherwise.

## When to Use
- Before checkpoint reports (5-10 min prior)
- Before marking any deliverable as "ready to deploy" or "needs review"
- On-demand for major work products

## How It Works

### Spawn Command
```
sessions_spawn with task containing:
- The work product(s) to review
- Context on what was requested
- Link to this skill for methodology
```

### Review Framework

The QA agent evaluates against 5 dimensions:

#### 1. COMPLETENESS
- Did the work actually fulfill the original ask?
- Are there obvious gaps or missing pieces?
- Was scope quietly reduced without acknowledgment?

#### 2. METHODOLOGY RIGOR
- Single data point vs. multiple angles?
- Were edge cases considered?
- Is sample size adequate for conclusions drawn?
- Would a skeptic poke holes in the approach?

#### 3. FACTUAL ACCURACY
- Are claims verifiable?
- Were primary sources checked?
- Any assumptions stated as facts?

#### 4. ACTIONABILITY
- Can someone act on this output directly?
- Or does it need "one more step" to be useful?
- Are recommendations specific or vague?

#### 5. QUALITY BAR
- Would this impress a smart, critical human?
- Does it feel rushed or thorough?
- Is it better than what a junior person would produce?

### Output Format

```
🔍 QA REVIEW — [Work Product Name]

📋 ORIGINAL ASK: [What was requested]

✅ PASSES:
- [Specific things done well]

⚠️ NEEDS IMPROVEMENT:
- [Issue]: [Specific problem] → [Suggested fix]

🔴 REDO REQUIRED:
- [Critical issue]: [Why it fails the bar] → [What needs to happen]

📊 DIMENSION SCORES:
- Completeness: [1-5]
- Rigor: [1-5]
- Accuracy: [1-5]
- Actionability: [1-5]
- Quality: [1-5]

🎯 VERDICT: [SHIP / REVISE / REDO]

💡 IF REVISING, PRIORITIZE:
1. [Most important fix]
2. [Second priority]
3. [Third priority]
```

### Severity Definitions

- **SHIP (🟢)**: Ready to deliver. Minor polish optional.
- **REVISE (🟡)**: Good foundation, but specific issues need addressing. 15-30 min of work.
- **REDO (🔴)**: Below the bar. Fundamental approach or completeness issues. Start fresh or major rework.

### QA Agent Principles

1. **Assume incomplete until proven otherwise** — Default stance is skepticism
2. **Be specific** — "This is weak" is useless. "The GEO analysis uses 1 query per platform; need 5-10 variations for statistical validity" is useful.
3. **Suggest fixes** — Don't just criticize, show the path forward
4. **Calibrate to stakes** — A Slack message needs less rigor than a client deliverable
5. **Time-box feedback** — If everything needs work, prioritize the top 3 issues

## Example Usage

### Spawning QA Review
```
sessions_spawn(
  agentId: "default",
  task: "QA REVIEW REQUEST\n\nRead skills/qa-agent/SKILL.md for methodology.\n\nWork product to review:\n[paste work or reference files]\n\nOriginal ask:\n[what was requested]\n\nProvide QA review in the specified format.",
  label: "qa-review"
)
```
