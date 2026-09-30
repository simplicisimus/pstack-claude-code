#!/usr/bin/env bash
# Tests for pstack/bin/pstack-role. Run from anywhere: tests/pstack-role.test.sh
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
bin="$root/pstack/bin/pstack-role"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pstack-role-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/agents"
for name in pstack-opus-max-review pstack-opus-max; do
	printf -- '---\nname: %s\n---\n\n<!-- pstack effort agent template 2 -->\n' "$name" >"$tmp/agents/$name.md"
done
printf -- '---\nname: pstack-haiku-low-review\n---\n' >"$tmp/agents/pstack-haiku-low-review.md"
while IFS= read -r line; do printf '%s\r\n' "$line"; done >"$tmp/pstack-models.md" <<'EOF'
# pstack model configuration. One line per role.
# @old: sonnet
@gpt: codex:gpt-6-astra:high
@grok: grok:grok-4.7
@free:
@chain: @gpt
@or: openrouter:deepseek/deepseek-r1:free
feature, refactoring: sonnet
hardest tasks: opus:max
how explorer: sonnet:high
interrogate reviewers: opus:max, @gpt, @grok, @free
swarm workers: @free
mechanical edits: inherit
why investigators: agent:my-investigator
reflect tooling: haiku:low
arena runners: opus:max, @gpt
arena cross-judge pool: @or, @chain, @missing, gpt-9
architect runners: @free
teach explainer: gpt-9
EOF

failures=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		printf '  expected:\n%s\n  actual:\n%s\n' "$2" "$3"
		failures=$((failures + 1))
	fi
}
run() { "$bin" --config "$tmp/pstack-models.md" "$@" 2>&1 | grep -v '^#'; }

check "panel of effort agent, bridges, and a disabled alias" \
"seat=1 value=opus:max subagent_type=pstack-opus-max-review
seat=2 value=@gpt=codex:gpt-6-astra:high subagent_type=pstack:codex-bridge bridge=codex brief_model=gpt-6-astra brief_effort=high brief_mode=review
seat=3 value=@grok=grok:grok-4.7 subagent_type=pstack:grok-bridge bridge=grok brief_model=grok-4.7 brief_effort=default brief_mode=review
seat=4 value=@free skip=alias-disabled" \
"$(run --seat review --default "opus, opus, sonnet" "interrogate reviewers")"

check "write seat uses the write variant of an effort agent" \
"seat=1 value=opus:max subagent_type=pstack-opus-max" \
"$(run --seat write --default opus "hardest tasks")"

check "a missing effort agent falls back to the plain model and says so" \
"seat=1 value=sonnet:high subagent_type=pstack:reviewer model=sonnet note=missing-pstack-sonnet-high-review-agent-so-session-effort-rerun-setup-pstack" \
"$(run --seat review --default sonnet "how explorer")"

check "a single-value role on a disabled alias falls back to the default" \
"seat=1 value=sonnet subagent_type=general-purpose model=sonnet note=disabled-alias-so-skill-default" \
"$(run --seat write --write-agent general-purpose --default sonnet "swarm workers")"

check "an effort agent from an older template still runs and is flagged" \
"seat=1 value=haiku:low subagent_type=pstack-haiku-low-review note=stale-pstack-haiku-low-review-agent-rerun-setup-pstack" \
"$(run --seat review --default sonnet "reflect tooling")"

check "inherit omits the model" \
"seat=1 value=inherit subagent_type=pstack:poteto-agent" \
"$(run --seat write --default sonnet "mechanical edits")"

check "agent: swaps the subagent type" \
"seat=1 value=agent:my-investigator subagent_type=my-investigator" \
"$(run --seat review --default sonnet "why investigators")"

check "a bridge in a write seat runs in a worktree" \
"seat=1 value=opus:max subagent_type=pstack-opus-max
seat=2 value=@gpt=codex:gpt-6-astra:high subagent_type=pstack:codex-bridge bridge=codex brief_model=gpt-6-astra brief_effort=high brief_mode=write isolation=worktree" \
"$(run --seat write --default "opus, opus, sonnet" "arena runners")"

check "openrouter ids keep their colons, bad entries fall back by position" \
"seat=1 value=@or=openrouter:deepseek/deepseek-r1:free subagent_type=pstack:openrouter-bridge bridge=openrouter brief_model=deepseek/deepseek-r1:free brief_effort=default brief_mode=review
seat=2 value=sonnet subagent_type=pstack:reviewer model=sonnet note=fallback-for-@chain-alias-must-name-one-plain-value
seat=3 value=opus subagent_type=pstack:reviewer model=opus note=fallback-for-@missing-undefined-alias
seat=4 value=opus subagent_type=pstack:reviewer model=opus note=fallback-for-gpt-9-unknown-value" \
"$(run --seat review --default "opus, sonnet" "arena cross-judge pool")"

check "a panel never refills a disabled alias" \
"seat=1 value=@free skip=alias-disabled" \
"$(run --seat review --panel --default "opus, opus, sonnet" "architect runners")"

check "a panel skips its disabled seat and runs the rest" \
"seat=1 value=opus:max subagent_type=pstack-opus-max-review
seat=2 value=@gpt=codex:gpt-6-astra:high subagent_type=pstack:codex-bridge bridge=codex brief_model=gpt-6-astra brief_effort=high brief_mode=review
seat=3 value=@grok=grok:grok-4.7 subagent_type=pstack:grok-bridge bridge=grok brief_model=grok-4.7 brief_effort=default brief_mode=review
seat=4 value=@free skip=alias-disabled" \
"$(run --seat review --panel --default "opus, opus, sonnet" "interrogate reviewers")"

check "an unusable value with no default is an error line" \
"seat=1 value=gpt-9 error=unknown-value no-default" \
"$(run --seat review "teach explainer")"

check "a role with no line uses the default list" \
"seat=1 value=sonnet subagent_type=pstack:poteto-agent model=sonnet" \
"$(run --seat write --default sonnet "bug-fix")"

check "a role name only matches the whole key" \
"seat=1 value=opus subagent_type=pstack:poteto-agent model=opus" \
"$(run --seat write --default opus "feature")"

check "the header names the source" \
'# role="bug-fix" seat=write source=default' \
"$("$bin" --config "$tmp/pstack-models.md" --seat write --default sonnet bug-fix | head -1)"

check "no config file still resolves the default" \
"seat=1 value=haiku subagent_type=pstack:reviewer model=haiku" \
"$("$bin" --config "$tmp/none.md" --seat review --default haiku "swarm workers" | grep -v '^#')"

"$bin" --config "$tmp/pstack-models.md" --seat review "unknown role" >/dev/null 2>&1
check "no line and no default is an error" "1" "$?"

"$bin" --seat sideways role >/dev/null 2>&1
check "a bad --seat is a usage error" "2" "$?"

[ "$failures" -eq 0 ] || {
	echo "$failures failed"
	exit 1
}
echo "all passed"
