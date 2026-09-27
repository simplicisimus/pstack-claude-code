---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

Fan out N parallel background workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Set N from the user or derive it from the shape. N is total workers, not the concurrency limit.
4. Pick the worker model from the `swarm workers` line in `~/.claude/pstack-models.md`. If the rule or that line is missing, use `sonnet`. Resolve the value per the value grammar and spawning rules in the **setup-pstack** skill (`opus`/`sonnet`/`haiku`/`fable` set `model`, `<model>:<effort>` spawns the generated `pstack-<model>-<effort>` agent (`-review` in a review seat), `inherit` omits it, `agent:<name>` sets `subagent_type`, `codex:<model>` spawns `pstack:codex-bridge`, `grok:<model>` spawns `pstack:grok-bridge`, `openrouter:<id>` spawns `pstack:openrouter-bridge`, each with the prompt-file bridge brief, `@<alias>` expands first). If it fails to spawn, use the default and say so. For a model race, name each arm's model up front.
5. Give each worker its own writable output when it writes. When workers verify or measure commits, each brief names the exact SHAs. A measurement brief also names the method (sample count, what one sample is, order). The worker records both in its result.

## Phase B: Fan out

Spawn all N workers in one message with `run_in_background: true` and the step 4 model. Workers that write use `subagent_type: general-purpose` and `isolation: "worktree"`, and a `codex:` or `grok:` writer gets `Mode: write`. Read-only workers are review seats: `pstack:reviewer` for a Claude model, `Mode: review` for a bridge, and no `isolation`. Use `isolation: "remote"` only when the user wants the work off this machine and remote agents are available.

When a worker must start from a non-default pushed branch, name the branch in its brief and have it check that branch out inside its worktree before any work.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. A worker that can prove a defect reports `ISSUES` and lists every issue it can prove, not only the first.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. Drop a result that does not record the SHAs and method its brief names, and rerun that worker once. After a second miss, record a gap. A gap does not count as a pass. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.

## pstack on Claude Code

`<pstack>` is `${CLAUDE_PLUGIN_ROOT}`. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms map per the Platform mapping table in `<pstack>/skills/poteto-mode/SKILL.md`.
