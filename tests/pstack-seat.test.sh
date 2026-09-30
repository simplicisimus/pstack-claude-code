#!/usr/bin/env bash
# Tests for pstack/bin/pstack-seat against fake codex and grok CLIs. Run from anywhere.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
seat="$root/pstack/bin/pstack-seat"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pstack-seat-test.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
marker="pstack-seat-test-$$"
cleanup() {
	pkill -f "$marker" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/repo"
cat >"$tmp/bin/codex" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >"$tmp/codex.args"
out="" cwd=""
while [ \$# -gt 0 ]; do
	case "\$1" in -o) out=\$2; shift ;; -C) cwd=\$2; shift ;; esac
	shift
done
cat >/dev/null
case "\${FAKE_MODE:-ok}" in
ok) echo "fake codex answer" >"\$out"; if [ "\${FAKE_WRITE:-}" = 1 ]; then echo change >"\$cwd/new-file.txt"; fi ;;
fail) echo "codex: model not found" >&2; exit 3 ;;
hang) bash -c 'exec -a $marker-grandchild sleep 600' & sleep 600 ;;
esac
EOF
cat >"$tmp/bin/grok" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >"$tmp/grok.args"
pwd >"$tmp/grok.cwd"
case "\${FAKE_MODE:-ok}" in
ok) echo "fake grok answer" ;;
hang) bash -c 'exec -a $marker-grandchild sleep 600' & sleep 600 ;;
esac
EOF
chmod +x "$tmp/bin/codex" "$tmp/bin/grok"
export PATH="$tmp/bin:$PATH"

git -C "$tmp/repo" init -q
git -C "$tmp/repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
tmp_note=""
case "$tmp/" in /tmp/* | /private/tmp/*) tmp_note=" note=repository-under-tmp-is-writable-by-grok" ;; esac
git -C "$tmp/repo" worktree add -q "$tmp/wt" -b wt 2>/dev/null

failures=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		printf '  expected: %s\n  actual:   %s\n' "$2" "$3"
		failures=$((failures + 1))
	fi
}
contains() {
	case "$3" in *"$2"*) echo "ok   $1" ;; *)
		echo "FAIL $1"
		printf '  expected to contain: %s\n  actual: %s\n' "$2" "$3"
		failures=$((failures + 1))
		;;
	esac
}
new_prompt() {
	local d
	d=$(mktemp -d "$tmp/seat.XXXXXX")
	echo "Review the repository." >"$d/prompt.md"
	echo "$d"
}

d=$(new_prompt)
out=$(cd "$tmp/repo" && "$seat" --cli codex --model m1 --effort high --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "codex review succeeds" "codex-bridge: model=m1 effort=high mode=review exit=0 answer=$d/answer.md bytes=18" "$out"
args=$(tr '\n' ' ' <"$tmp/codex.args")
contains "codex review is read-only on the repository" "-s read-only --skip-git-repo-check --ephemeral --color never -C $tmp/repo" "$args"
contains "codex gets the effort" "-c model_reasoning_effort=high" "$args"

d=$(new_prompt)
out=$(FAKE_MODE=fail "$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "a failing CLI reports its exit code and log" "codex-bridge: FAILED exit=3 bytes=0: codex: model not found " "$out"

d=$(new_prompt)
start=$(date +%s)
out=$(FAKE_MODE=hang "$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md" --deadline 2)
took=$(($(date +%s) - start))
contains "a hung codex stops at the deadline" "codex-bridge: FAILED deadline=2s" "$out"
check "the deadline returns promptly" "yes" "$([ "$took" -le 8 ] && echo yes || echo "no, ${took}s")"
sleep 1
check "the CLI's whole process group is gone" "0" "$(pgrep -f "$marker-grandchild" | wc -l | tr -d ' ')"

d=$(new_prompt)
out=$(FAKE_MODE=hang BASH_MAX_TIMEOUT_MS=4000 "$seat" --cli grok --model g1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
contains "the default deadline follows BASH_MAX_TIMEOUT_MS, grok included" "grok-bridge: FAILED deadline=2s" "$out"
sleep 1
check "grok's process group is gone too" "0" "$(pgrep -f "$marker-grandchild" | wc -l | tr -d ' ')"

d=$(new_prompt)
out=$("$seat" --cli grok --model g1 --effort low --mode review --repo "$tmp/repo" --prompt "$d/prompt.md")
check "grok review succeeds, noting a repository under /tmp" "grok-bridge: model=g1 effort=low mode=review exit=0 answer=$d/answer.md bytes=17$tmp_note" "$out"
check "grok review runs from a scratch directory" "$d/cwd" "$(cat "$tmp/grok.cwd")"
contains "grok review keeps MCP gateways and edits out" "--disallowed-tools search_replace,search_tool,use_tool" "$(tr '\n' ' ' <"$tmp/grok.args")"
contains "grok review prompt names the repository" "The repository for this task is at $tmp/repo." "$(cat "$d/prompt.grok.md")"

d=$(new_prompt)
out=$(cd "$tmp/repo" && "$seat" --cli codex --model m1 --mode write --repo "$tmp/repo" --prompt "$d/prompt.md")
check "write outside a linked worktree runs as review" "codex-bridge: model=m1 effort=default mode=review exit=0 answer=$d/answer.md bytes=18 note=write-refused-not-in-a-linked-worktree" "$out"

d=$(new_prompt)
out=$(cd "$tmp/wt" && FAKE_WRITE=1 "$seat" --cli codex --model m1 --mode write --repo "$tmp/repo" --prompt "$d/prompt.md")
check "write inside a linked worktree writes there and lists the change" "codex-bridge: model=m1 effort=default mode=write exit=0 answer=$d/answer.md bytes=18
?? new-file.txt" "$out"

d=$(new_prompt)
out=$("$seat" --cli codex --model m1 --mode review --repo "$tmp/repo" --prompt "$d/prompt.md" --deadline soon)
check "a non-numeric deadline is refused" "codex-bridge: FAILED --deadline must be a number of seconds" "$out"

out=$("$seat" --cli cursor --model m1 --prompt /nonexistent)
check "an unknown CLI is refused" "pstack-seat: FAILED --cli must be codex or grok" "$out"

[ "$failures" -eq 0 ] || {
	echo "$failures failed"
	exit 1
}
echo "all passed"
