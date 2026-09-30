#!/usr/bin/env bash
# Checks which `effort:` frontmatter Claude Code applies to a subagent.
#
# A headless session at --effort medium spawns plugin agents with effort low, high, and none,
# the low one again with a model override, and a --agents session agent with effort low.
# Each subagent transcript records the effort of every turn in `perTurnEffort`, so the table
# shows what actually ran. Needs a logged-in `claude` CLI and python3. Costs a few Sonnet turns.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

if ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
	echo "effort-probe: the claude CLI is not logged in. Run \`claude /login\` in a terminal, then retry." >&2
	exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/effort-probe.XXXXXX")
cd "$work"

session_agents='{"probe-session-low":{"description":"Effort probe fixture. Spawn only when a test names it.","prompt":"Reply with exactly: OK","model":"sonnet","effort":"low"}}'
prompt="This is an automated test of subagent settings. In ONE message, make exactly these five Agent tool calls in parallel. Give each run_in_background false, the prompt 'Reply with exactly: OK', and the description shown:
1. description 'arm plugin-low', subagent_type 'effort-probe:probe-low', no model parameter
2. description 'arm plugin-high', subagent_type 'effort-probe:probe-high', no model parameter
3. description 'arm plugin-none', subagent_type 'effort-probe:probe-none', no model parameter
4. description 'arm plugin-low-opus', subagent_type 'effort-probe:probe-low', model 'opus'
5. description 'arm session-low', subagent_type 'probe-session-low', no model parameter
After all five return, reply with just DONE. Use no other tool."

claude -p --plugin-dir "$here/plugin" --agents "$session_agents" --model sonnet --effort medium \
	--max-turns 6 --output-format json "$prompt" >"$work/result.json"

python3 - "$work/result.json" "$config" <<'PY'
import glob, json, os, sys

result = json.load(open(sys.argv[1]))
if result.get("is_error"):
    sys.exit(f"effort-probe: the session failed: {result.get('result')}")
session = result["session_id"]
dirs = glob.glob(os.path.join(sys.argv[2], "projects", "*", session, "subagents"))
if not dirs:
    sys.exit(f"effort-probe: no subagent transcripts for session {session}")

expected = {
    "arm plugin-low": "low",
    "arm plugin-high": "high",
    "arm plugin-none": "medium",
    "arm plugin-low-opus": "low",
    "arm session-low": "low",
}
seen = {}
for meta_path in glob.glob(os.path.join(dirs[0], "agent-*.meta.json")):
    meta = json.load(open(meta_path))
    arm = meta.get("description", "")
    efforts, models = set(), set()
    with open(meta_path.replace(".meta.json", ".jsonl")) as transcript:
        for line in transcript:
            event = json.loads(line)
            if event.get("type") == "assistant":
                efforts.add(str(event.get("perTurnEffort")))
                models.add(event["message"].get("model", "?"))
    seen[arm] = (meta.get("agentType", "?"), ",".join(sorted(models)), ",".join(sorted(efforts)))

print(f"{'arm':<22}{'agent type':<28}{'model':<20}{'ran at':<10}expected")
for arm, want in expected.items():
    agent, model, effort = seen.get(arm, ("missing", "-", "-"))
    print(f"{arm:<22}{agent:<28}{model:<20}{effort:<10}{want}")

plugin_low = seen.get("arm plugin-low", ("", "", ""))[2]
plugin_high = seen.get("arm plugin-high", ("", "", ""))[2]
if plugin_low == "low" and plugin_high == "high":
    print("verdict: Claude Code applies effort frontmatter to plugin agents.")
elif plugin_low == plugin_high == "medium":
    print("verdict: Claude Code ignores effort frontmatter in plugin agents. They run at the session effort.")
else:
    print("verdict: inconclusive. Check the arms above.")
PY
