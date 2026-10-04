# pstack for Claude Code

A Claude Code port of [pstack](https://github.com/cursor/plugins/tree/main/pstack) v0.15.9 by [poteto](https://x.com/poteto) (Lauren Tan), MIT licensed. The upstream README explains the philosophy. This file covers what differs on Claude Code.

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

Then run `/pstack:setup-pstack` once to choose models per role. After updating from 0.15.5-claude.8 or earlier, run it once more to delete the effort agents those versions generated (see [Claude effort per role](#claude-effort-per-role)).

## Use

```
/pstack:poteto-mode this pr has a subtle bug where the scroll drifts every 750ms even when idle. repro first, then fix and verify.
/pstack:how do we cancel runs?
/pstack:interrogate review this pr.
```

Every skill except `setup-pstack` and `typescript-best-practices` is user-invocable only (`disable-model-invocation: true`, as upstream). That keeps 47 skill descriptions out of every session's context. `typescript-best-practices` loads by itself when Claude works on `.ts` and `.tsx` files, through its `paths` field. `poteto-mode` reaches the other skills by reading `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` directly.

## What changed from the Cursor version

| Cursor | Claude Code port |
|---|---|
| `.cursor-plugin/plugin.json` | `.claude-plugin/plugin.json` |
| `Task` tool, `generalPurpose` | Agent tool, `general-purpose` |
| `readonly: true` | `pstack:reviewer`, an agent with no Edit, Write, NotebookEdit, or Agent tools (the Agent tool has no readonly flag) |
| `environment: "cloud"` | `isolation: "worktree"` background agents, or `isolation: "remote"` when wanted |
| `~/.cursor/rules/pstack-models.mdc` (always-applied rule) | `~/.claude/pstack-models.md`, read at spawn time |
| Model slugs (`grok-4.7-xhigh-fast`, `gpt-5.6-sol-max`, `claude-opus-5-5-max`) | `opus`, `sonnet`, `haiku`, `fable`, `<model>:<effort>` (for example `opus:max`), `inherit`, `agent:<subagent_type>`, `codex:<model>[:<effort>]`, `grok:<model>[:<effort>]`, or `openrouter:<model-id>` |
| Reasoning-effort budgets | `max` / `balanced` / `lean` model-tier budgets, plus a fixed effort per role with `<model>:<effort>` |
| `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/<session-id>.jsonl` |
| `subagent_type: "poteto-agent"`, `"Comment Sicko"` | `pstack:poteto-agent`, `pstack:comment-sicko` |
| `mode: true` sticky mode with `reminder` | A `UserPromptSubmit` hook in `poteto-mode`'s frontmatter that repeats the reminder on every prompt after `/pstack:poteto-mode` |
| The agent store, named in the system prompt | `${CLAUDE_PLUGIN_DATA}/store`, named in `poteto-mode` |
| Todo list | `TaskCreate` and `TaskUpdate`, or `TodoWrite`, when the session has them, otherwise a file |
| `cursor-team-kit` (`deslop`, `control-ui`, `control-cli`) | `deslop` copied into `~/.claude/skills/` (falls back to the built-in `simplify` skill), built-in browser tools, Bash, `run` skill |
| `create-skill` (Cursor built-in) | `skill-creator` skill |

[`skills/poteto-mode/references/claude-code.md`](pstack/skills/poteto-mode/references/claude-code.md) maps every Cursor term still left in the playbooks.

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
- **Seats end before the Bash timeout.** `pstack-seat` stops the CLI and its child processes 30 seconds before `BASH_MAX_TIMEOUT_MS`. Claude Code would otherwise move the command to the background and keep it running after the bridge gave up. From the main conversation, a review seat can instead run `pstack-seat` as a background Bash task, which has no timeout.
- **Claude review seats** run as `pstack:reviewer`, or `pstack:reviewer-<effort>` at a fixed effort. Neither has edit tools or can start subagents, and both keep Bash and MCP tools. A `PreToolUse` hook blocks the Bash and Monitor commands in those seats that write outside scratch directories, edit in place, change git or GitHub state, or install packages.

### Claude effort per role

A plain `opus` seat runs at your session's effort level. For a fixed level, write `<model>:<effort>`, for example `opus:max` for the review panels or `opus:high` for explorers.

```
interrogate reviewers: opus:max, @gpt, @grok
hardest tasks: opus:max
how explorer: opus:high
```

Claude Code's Agent tool has no effort parameter, and a subagent takes its effort from the `effort` frontmatter of its definition. So pstack ships its two seat agents at each effort level:

- `pstack:reviewer-<effort>`, a read-only review seat;
- `pstack:poteto-agent-<effort>`, a code delegate in poteto's style.

`<effort>` is `low`, `medium`, `high`, `xhigh`, or `max`. Neither agent sets a model. `pstack-role` picks the agent for the seat and passes the model in the Agent call. `/tasks` shows each seat's effort next to its model.

Claude Code lists every plugin agent in every session, used or not. Each of the ten has a one-sentence description, and `claude plugin details pstack` estimates that together they add about 230 tokens to every session.

Tested on Claude Code 2.1.284 with [`tests/effort-probe/run.sh`](tests/effort-probe/run.sh). From a session at `medium`, `pstack:reviewer-low` ran every turn at `low` and `pstack:poteto-agent-high` ran every turn at `high`, both on Sonnet. Plugin agents set to `low`, `high`, and no effort ran at `low`, `high`, and `medium`, even when the call chose another model. Each subagent transcript records this as `perTurnEffort`.

Versions up to 0.15.5-claude.8 generated user agents in `~/.claude/agents/` for these values instead. Re-run `/pstack:setup-pstack` once to delete them. It removes only the agents it generated.

### Settings worth adding

External seats run in the foreground, and the Bash tool's timeout is 10 minutes by default. Write seats start from your default branch unless told otherwise. Newer models, such as Opus 5.5, get no todo tools unless you enable them, and pstack's playbooks start with a todo list. All three are settings in `~/.claude/settings.json`:

```json
{
  "env": {
    "BASH_MAX_TIMEOUT_MS": "1800000",
    "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"
  },
  "worktree": { "baseRef": "head" }
}
```

Without the timeout change, keep panel effort at `high` or below.

### What leaves your machine

External seats send code and diffs to that provider. `reflect` sends the session transcript. Free and stealth OpenRouter models may log prompts, and the OpenRouter bridge skips `.env`, key, and credential files, plus anything git ignores. Keep panels Claude-only for code you cannot share.

## Not ported

- `make-bot-ui`. It targets Cursor Automations webhooks.
- The `benny` automation pack and the `docs/guide`. Both are Cursor-specific.

The `scripts/` tooling (`watch-pr`, `orch`) is included unchanged, apart from a `bun.lock` that names the renamed package. It needs [Bun](https://bun.sh), and it installs its dependencies next to the scripts on first run.

## Changes in this fork

Relative to [mix64/pstack-claude-code@cbb2b75](https://github.com/mix64/pstack-claude-code/tree/cbb2b75), plus mix64's update to upstream 0.15.9 ([f51e899](https://github.com/mix64/pstack-claude-code/commit/f51e899)):

- **Claude Code conformance.**
  - **poteto-mode stays on.** A `UserPromptSubmit` hook in its frontmatter repeats upstream's `reminder` on every prompt, as Cursor's `mode: true` did. Its routing sections now come first, because after compaction Claude Code keeps only the first 5,000 tokens of an invoked skill.
  - **Cursor runtime terms mapped.** `references/claude-code.md` holds the map. The agent store is `${CLAUDE_PLUGIN_DATA}/store`. Audit ticks run on the `loop` skill. Swarm, orchestrate, and the autopilots stay under Claude Code's cap of 20 running subagents. A todo list falls back to a file on models without todo tools.
  - **Transcripts found the Claude Code way.** poteto-mode names the session ID and transcript. `reflect` matches the first `user` line, and its reviewers look for `Bash` calls, not Cursor's `Shell`.
  - **External seats stop in time.** `pstack-seat` stops the CLI 30 seconds before the Bash timeout. Before, Claude Code moved the timed-out command to the background, the bridge reported `FAILED`, and the CLI kept running on your subscription. The bridges also cap their turns and skip CLAUDE.md.
  - **One role resolver.** `bin/pstack-role` applies the value grammar that seven skills used to restate. `--panel` keeps a disabled alias from being refilled in a panel.
  - **Review seats enforced.** A `PreToolUse` hook blocks Bash and Monitor commands that write files or change the repository in `pstack:reviewer` and its fixed-effort copies.
  - **Plugin paths from Claude Code.** `pstack:poteto-agent`, its fixed-effort copies, and the bridges get `${CLAUDE_PLUGIN_ROOT}` from their own definitions instead of searching the plugin cache.
  - **Smaller fixes.** `typescript-best-practices` loads for `.ts` files again, since its `paths` did nothing next to `disable-model-invocation`. `bun.lock` names the renamed package. `setup-pstack` offers at most four AskUserQuestion options and the todo-tools setting. Skills show argument hints. Autopilot slop-strips use `deslop` first. The `how` prompts no longer assume Glob and Grep tools. The marketplace names its owner and describes itself.
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
- **Claude effort per role.** The `<model>:<effort>` value and the fixed-effort agents that ship with the plugin.
- **Bounded agent context.** Every call re-reads an agent's whole context, so long-lived agents cost the most. In one measured overnight autopilot run, 9 resumed owners and the root were 56% of the token cost, and 428 short-lived lanes were 42%.
  - Agents end after their task and hand long work to a fresh agent through a file.
  - The autopilots start a fresh owner agent for each fix round and keep the root's context small.
  - Audit lanes run before live lanes, lanes report in a few lines that point at files, and a PR parks for the operator after three unclean rounds.
- **Smaller fixes.**
  - `automate-me` uses AskUserQuestion's real `multiSelect` parameter and its limit of 4 options.
  - The arena cross-judge default matches `setup-pstack`.
  - Disabled aliases drop their seat instead of falling back.
  - `plugin.json` points at this repository.

## Development

The tests need bash and node. CI runs them on Linux and macOS, with `claude plugin validate --strict`, the effort-agent check, and the Bun suites for `scripts/`.

```
tests/pstack-role.test.sh
tests/pstack-seat.test.sh
tests/review-seat-guard.test.sh
tools/gen-effort-agents --check
```

[`tools/gen-effort-agents`](tools/gen-effort-agents) writes the ten fixed-effort agents from `pstack/agents/reviewer.md` and `pstack/agents/poteto-agent.md`. Edit those two, rerun it, and commit what it writes.

`tests/effort-probe/run.sh` checks which `effort` frontmatter Claude Code applies to subagents, pstack's effort agents included. It needs a logged-in `claude` CLI and costs a few Sonnet turns.

Eval cases live in [`pstack/evals/`](pstack/evals). `claude plugin eval ./pstack --ablation none` runs them, and each run is a real Claude session on your account.

To release, bump `version` in `pstack/.claude-plugin/plugin.json`, then run `claude plugin tag ./pstack`. It checks that the manifests agree and creates the `pstack--v<version>` tag.

## License

MIT. The original work is Copyright (c) 2026 Lauren Tan, see [LICENSE](LICENSE). This port keeps that notice and is distributed under the same license. It is not affiliated with or endorsed by Cursor or Anysphere.
