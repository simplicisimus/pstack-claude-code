# pstack for Claude Code

A Claude Code port of [pstack](https://github.com/cursor/plugins/tree/main/pstack) v0.15.5 by [poteto](https://x.com/poteto) (Lauren Tan), MIT licensed. The upstream README explains the philosophy. This file covers what differs on Claude Code.

This is a fork of [mix64/pstack-claude-code](https://github.com/mix64/pstack-claude-code). It adds Grok panel seats, rebuilds the external-model bridges, and fixes bugs in the port. See [Changes in this fork](#changes-in-this-fork).

## Install

From GitHub:

```
/plugin marketplace add simplicisimus/pstack-claude-code
/plugin install pstack@pstack-claude-code
```

From a local clone:

```
/plugin marketplace add /path/to/pstack-claude-code
/plugin install pstack@pstack-claude-code
```

Then run `/pstack:setup-pstack` once to choose models per role.

## Use

```
/pstack:poteto-mode this pr has a subtle bug where the scroll drifts every 750ms even when idle. repro first, then fix and verify.
/pstack:how do we cancel runs?
/pstack:interrogate review this pr.
```

Every skill except `setup-pstack` is user-invocable only (`disable-model-invocation: true`, as upstream). That keeps 45 skill descriptions out of every session's context. `poteto-mode` reaches the others by reading `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` directly.

## What changed from the Cursor version

| Cursor | Claude Code port |
|---|---|
| `.cursor-plugin/plugin.json` | `.claude-plugin/plugin.json` |
| `Task` tool, `generalPurpose` | Agent tool, `general-purpose` |
| `readonly: true` | `pstack:reviewer`, an agent with no Edit, Write, or NotebookEdit tools (the Agent tool has no readonly flag) |
| `environment: "cloud"` | `isolation: "worktree"` background agents, or `isolation: "remote"` when wanted |
| `~/.cursor/rules/pstack-models.mdc` (always-applied rule) | `~/.claude/pstack-models.md`, read at spawn time |
| Model slugs (`grok-4.7-xhigh-fast`, `gpt-5.6-sol-max`, `claude-opus-5-5-max`) | `opus`, `sonnet`, `haiku`, `fable`, `inherit`, `agent:<subagent_type>`, `codex:<model>[:<effort>]`, `grok:<model>[:<effort>]`, or `openrouter:<model-id>` |
| Reasoning-effort budgets | `max` / `balanced` / `lean` model-tier budgets |
| `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/<session-id>.jsonl` |
| `subagent_type: "poteto-agent"`, `"Comment Sicko"` | `pstack:poteto-agent`, `pstack:comment-sicko` |
| `mode: true` sticky mode with `reminder` | A sticky instruction at the top of `poteto-mode` (invoked skill content stays in context) |
| `cursor-team-kit` (`deslop`, `control-ui`, `control-cli`) | `deslop` copied into `~/.claude/skills/` (falls back to the built-in `simplify` skill), built-in browser tools, Bash, `run` skill |
| `create-skill` (Cursor built-in) | `skill-creator` skill |

The "Platform mapping" table in `skills/poteto-mode/SKILL.md` tells the agent how to translate any Cursor term still left in the playbooks.

## Multi-model panels

Upstream runs `arena`, `architect`, and `interrogate` across Claude, GPT, and Grok on purpose: the adversarial signal comes from model diversity. The skill defaults here are Claude only, so the plugin works with nothing else installed. Three bridge agents bring other vendors back without a proxy:

| Value | Bridge | Needs | Fits |
|---|---|---|---|
| `codex:<model>[:<effort>]` | `pstack:codex-bridge` runs `codex exec` | [Codex CLI](https://github.com/openai/codex) logged in (`codex login`), so it uses your ChatGPT plan | Every seat. Codex reads files and runs commands itself. |
| `grok:<model>[:<effort>]` | `pstack:grok-bridge` runs `grok` headless | Grok Build CLI logged in (`grok models` lists models), so it uses your SuperGrok plan | Every seat. Grok reads files and runs commands itself. |
| `openrouter:<model-id>` | `pstack:openrouter-bridge` runs `bin/openrouter-ask` | `OPENROUTER_API_KEY` in the environment | Review, judge, and design seats. Text in, text out. |

When `/pstack:setup-pstack` finds Codex or Grok, it recommends one seat per vendor, as upstream does:

```
@gpt: codex:gpt-6-astra:high
@grok: grok:grok-4.7:high
arena runners: opus, @gpt, @grok
arena cross-judge pool: @gpt, @grok
architect runners: opus, @gpt, @grok
interrogate reviewers: opus, @gpt, @grok
```

Leave an alias empty (`@grok:`) to drop its seats. A failed or timed-out external seat reruns on the skill's default model, and the reply says so.

### How a bridge seat runs

The parent writes the whole prompt to a private file and spawns the bridge with a five-line brief (model, effort, mode, repository, prompt file). Codex and Grok seats run through [`bin/pstack-seat`](pstack/bin/pstack-seat), which writes the answer next to the prompt and prints one status line. The parent reads the answer file itself, so the small relay model never retypes the prompt or the answer.

- **Review seats** cannot write to your checkout. Codex runs with `-s read-only`. Grok runs in its `workspace` sandbox from a scratch directory and reads the repository by absolute path. Its `read-only` sandbox is not used because it refuses to start on some Macs, for example when `/var/run/docker.sock` is a symlink. The `workspace` sandbox also lets Grok write under `/tmp`, so a repository under `/tmp` is not protected, and the status line says so.
- **Write seats** run only inside a linked git worktree, which the Agent tool creates with `isolation: "worktree"`. Asked to write anywhere else, including your main checkout, the seat runs as review and the status line says why. Changes are left uncommitted for the parent to review.
- **MCP servers stay out.** Codex runs with `--ignore-user-config`, so your Codex MCP servers, hooks, and notify program don't run, and your Codex login still works. Grok runs without `search_tool` and `use_tool`, its gateway to MCP servers. MCP servers run outside both sandboxes, so either CLI could otherwise edit files through them.
- **Claude review seats** run as `pstack:reviewer`, which has no edit tools but keeps Bash and MCP tools.

### Settings worth adding

External seats run in the foreground and Claude Code's Bash tool stops them after 10 minutes by default. Write seats start from your default branch unless told otherwise. Both are settings in `~/.claude/settings.json`:

```json
{
  "env": { "BASH_MAX_TIMEOUT_MS": "1800000" },
  "worktree": { "baseRef": "head" }
}
```

Without the timeout change, keep panel effort at `high` or below.

### What leaves your machine

External seats send code and diffs to that provider. `reflect` sends the session transcript. Free and stealth OpenRouter models may log prompts, and the OpenRouter bridge skips `.env`, key, and credential files, plus anything git ignores. Keep panels Claude-only for code you cannot share.

## Not ported

- `make-bot-ui`. It targets Cursor Automations webhooks.
- The `benny` automation pack and the `docs/guide`. Both are Cursor-specific.

The `scripts/` tooling (`watch-pr`, `orch`) is included unchanged. It needs [Bun](https://bun.sh).

## Changes in this fork

Relative to [mix64/pstack-claude-code@cbb2b75](https://github.com/mix64/pstack-claude-code/tree/cbb2b75):

- **Grok seats.** The `grok:<model>[:<effort>]` value and the `pstack:grok-bridge` agent.
- **Bridges rebuilt.** Codex and Grok seats run through `bin/pstack-seat`. The parent writes the prompt file, the bridge returns the answer file's path, and effort can be set per seat.
  - Write seats find their worktree themselves. Before, a Codex write seat quietly fell back to review because the parent could not tell it the worktree path.
  - Codex ignores your Codex user config, so its MCP servers and hooks can't get around its sandbox.
- **Real read-only seats.** The `pstack:reviewer` agent replaces "tell it not to edit files" in `interrogate`, `how`, `why`, `reflect`, the arena cross-judge, and read-only swarm workers.
- **The plan checker accepts the port's own plan skeleton.** `check-plan.mjs` still required `git show origin/main:`, which the port had replaced with reads from disk.
- **Comment Sicko has its tools again.** The port had limited it to read-only tools, but its job is deleting comments and running `/how` and `/why`.
- **Executable bits restored** on `check-plan.mjs`, `orch.ts`, `watch-pr`, `worktree-audit.sh`, and `log.sh`.
- **Worktree cleanup is safer.**
  - The playbook no longer suggests deleting `~/.claude/projects/` session logs, which `recall` and session pickup read.
  - `worktree-audit.sh` finds sessions filed under a worktree's own path.
  - It falls back to `grep` when `rg` isn't installed. Before, it silently found no chats and could mark a live worktree safe to delete.
- **Real `/deslop` before commit.** pstack runs Cursor's `deslop` skill when it is installed as a user skill, and only falls back to `simplify` without it. `simplify` targets reuse and efficiency, not AI slop.
- **Smaller fixes.**
  - `automate-me` uses AskUserQuestion's real `multiSelect` parameter and its limit of 4 options.
  - The arena cross-judge default matches `setup-pstack`.
  - Disabled aliases drop their seat instead of falling back.
  - `plugin.json` points at this repository.

## License

MIT. The original work is Copyright (c) 2026 Lauren Tan, see [LICENSE](LICENSE). This port keeps that notice and is distributed under the same license. It is not affiliated with or endorsed by Cursor or Anysphere.
