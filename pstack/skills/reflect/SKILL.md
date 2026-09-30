---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

## When to invoke

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

The parent finds its own transcript file before fanning out. Its transcript is `~/.claude/projects/<slug>/<session-id>.jsonl`, where `<slug>` is the working directory's absolute path with every non-alphanumeric character replaced by `-` (so `C:\Users\you\proj` becomes `C--Users-you-proj`). The session ID is `${CLAUDE_SESSION_ID}` when you run this skill as `/pstack:reflect`. When poteto-mode, another pstack skill, or a brief sent you here, use the session ID it names. Use that directory. Do not glob across `~/.claude/projects/*/`. That crosses workspace boundaries and reads private chats from unrelated projects.

Without an ID, list the candidates in that one directory:

```bash
ls -t ~/.claude/projects/<slug>/*.jsonl 2>/dev/null | head -10
```

Claude Code keeps one `<session-id>.jsonl` per session and each subagent's transcript at `<session-id>/subagents/agent-<id>.jsonl`. A session file starts with event lines such as `queue-operation`. For each candidate, find the first line whose `type` is `user` and check that its `message.content`, a string or a list of text blocks, holds the conversation's opening user prompt. Take the matching path. If no path resolves, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

One message, three `Agent` calls, `subagent_type: pstack:reviewer`, with `model` set as below. Reviewers need MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript). `pstack:reviewer` keeps MCP access and has no edit tools. A `codex:`, `grok:`, or `openrouter:` reviewer receives the session transcript and has no MCP access, so use one only when the user is fine sending the transcript to that provider.

Each reviewer and the synthesizer name a role line in `~/.claude/pstack-models.md` (written by `/setup-pstack`) and a default. Resolve it with `pstack-role --seat review --default <default> '<role line>'`. It applies the value grammar in the **setup-pstack** skill, falls back to the default when the file or the line is missing, and prints the `subagent_type` and `model` to use, which are the ones listed below for a plain Claude model, or the brief of a bridge seat. If a spawn fails or a bridge replies `FAILED`, rerun it on the default and say so.

| Lens | Role line | Default `model` | Prompt template |
|---|---|---|---|
| Judgment | `reflect judgment, divergent, synthesizer` | `opus` | `references/judgment-reviewer.md` |
| Tooling | `reflect tooling` | `sonnet` | `references/tooling-reviewer.md` |
| Divergent | `reflect judgment, divergent, synthesizer` | `opus` | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the `Agent` response body.

### 3. Synthesize

One `Agent` call, `subagent_type: pstack:reviewer`, with `model` from the `reflect judgment, divergent, synthesizer` line (default `opus`). The synthesizer's quality check includes spot-verifying citations, which can require MCP access, and `pstack:reviewer` keeps it. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

Backlog items file to whatever devex / backlog tracker your team uses automatically. Only the Accepted list waits for approval.

For each approved Accepted item, follow the Routing field exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the `skill-creator` skill when available and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to `create-skill` and run its description-optimization loop.
- `new skill via create-skill: <kebab-name>`: hand creation to `create-skill`. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.

## pstack on Claude Code

When you run this skill directly, `<pstack>` is `${CLAUDE_PLUGIN_ROOT}`, `<store>` is `${CLAUDE_PLUGIN_DATA}/store`, and this session's ID is `${CLAUDE_SESSION_ID}`. When poteto-mode, another pstack skill, or a brief sent you here, use the values it names. Other pstack skills named here (in bold, or as `principle-*`) live at `<pstack>/skills/<name>/SKILL.md`. They are user-invocable only, so Read them with the Read tool instead of the Skill tool. Per-role models come from `~/.claude/pstack-models.md` (see the **setup-pstack** skill). Cursor-specific terms, and a todolist in a session without a todo tool, map per `<pstack>/skills/poteto-mode/references/claude-code.md`.
