# pstack on Claude Code

The playbooks were written for Cursor. Each row maps a Cursor term to what Claude Code has. `<pstack>` and `<store>` are the paths named in the "Running on Claude Code" section of the **poteto-mode** skill.

| Playbook says | On Claude Code |
|---|---|
| `Task` subagent, `subagent_type: general-purpose` | Agent tool, same `subagent_type`. |
| cloud agent, `environment: "cloud"` | Agent with `isolation: "worktree"` and `run_in_background: true`. Use `isolation: "remote"` only when the user wants the work off this machine and remote agents are available. |
| readonly / Ask mode | `subagent_type: "pstack:reviewer"`, which has no edit tools but keeps Bash and MCP. `Explore` for pure search. |
| Resume an agent | `SendMessage` to its agent ID or name. |
| Stand down or stop an agent | `TaskStop` with its agent ID, name, or task ID. |
| Cursor dashboard, agent status | Background task notifications, each agent's output, and `/tasks`. Never poll with `sleep`. |
| Cursor restart | Claude Code restart. Background local agents die with the session. |
| Cloud concurrency limit | Claude Code refuses a new subagent while 20 are running in the session, and the error says not to retry. `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` changes the cap. Keep a rolling window below it, and start queued work as agents finish. |
| The agent store, "path in the system prompt" | `<store>`. Create a directory in it with `mkdir -p` on first use. |
| todolist | `TaskCreate` and `TaskUpdate`, or `TodoWrite`, when the session has them. Newer models, such as Opus 5.5, Sonnet 5.5, and Fable 5.1, get them only in background or cloud sessions or with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Without them, keep the list in a file of its own under `<store>/todo/`, named for the task and the date, update it as steps finish, and show it at each checkpoint. |
| `/goal` | Claude Code's `/goal`, which only the operator can type. Give them the exact line to paste, for example `/goal <condition>, or stop after <N> turns`. After each turn a small model judges the condition from the transcript alone, so write it as output you will show, such as a command's result. |
| `/loop`, a wake chain, a monitored-shell sleep with an output-notification sentinel | The `loop` skill, which you can invoke yourself. `30m <tick prompt>` gives a fixed cadence, and no interval lets you pace it. The **Monitor** tool or a background Bash command handles event waits. |
| A cloud root's cloud-sleeper wake chain | A scheduled remote agent through the `schedule` skill. |
| `control-ui` (browser, Electron, web) | The built-in browser tools (`mcp__Claude_Browser__*`), or Claude in Chrome when the user asks for it. The `run` skill launches the app. |
| `control-cli` (CLIs, TUIs) | Bash, and the `run` skill for launching. |
| `/deslop` from `cursor-team-kit` | The `deslop` skill when installed (copy `cursor-team-kit/skills/deslop/SKILL.md` to `~/.claude/skills/deslop/`). Otherwise the built-in `simplify` skill over the diff. |
| `create-skill` (Cursor built-in) | The `skill-creator` skill when available. Otherwise the **Authoring a skill** playbook alone. |
| Bugbot, cloud-agent PR tools | Whatever PR reviewers and `gh` the repo has. |
| The repo's `AGENTS.md` files and rules | Its `CLAUDE.md` and `AGENTS.md` files and `.claude/rules/`. |
| Glob and Grep tools | Absent by default on macOS, Linux, and WSL. Use `find` and `grep` through Bash there. |
| A `Shell` tool call in a transcript | A `Bash` tool call. |
| `agent-transcripts/<id>/<id>.jsonl` | `~/.claude/projects/<slug>/<session-id>.jsonl`, where `<slug>` is the working directory's absolute path with every non-alphanumeric character replaced by `-`. A subagent is `<session-id>/subagents/agent-<id>.jsonl`, beside a `.meta.json` that names its agent type. Early lines are events such as `queue-operation`. Chat lines have `type` `user` or `assistant`, and a user message's `message.content` is a string or a list of blocks. |
