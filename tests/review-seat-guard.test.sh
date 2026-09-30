#!/usr/bin/env bash
# Tests for pstack/hooks/review-seat-guard, fed the JSON a PreToolUse hook receives. Needs node.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
guard="$root/pstack/hooks/review-seat-guard"
failures=0
count=0

decide() {
	local agent=$1 command=$2 tool=${3:-Bash} input out
	input=$(node -e '
		const [command, agent, tool] = process.argv.slice(1);
		const event = { session_id: "test", hook_event_name: "PreToolUse", tool_name: tool, tool_input: { command } };
		if (agent) Object.assign(event, { agent_id: "a1", agent_type: agent });
		process.stdout.write(JSON.stringify(event));' "$command" "$agent" "$tool")
	out=$(printf '%s' "$input" | "$guard")
	case "$out" in *'"permissionDecision":"deny"'*) echo deny ;; '') echo allow ;; *) echo "unexpected: $out" ;; esac
}
expect() {
	local want=$1 agent=$2 command=$3 tool=${4:-Bash} got
	got=$(decide "$agent" "$command" "$tool")
	count=$((count + 1))
	if [ "$got" != "$want" ]; then
		printf 'FAIL expected %s, got %s  [%s %s] %q\n' "$want" "$got" "$agent" "$tool" "$command"
		failures=$((failures + 1))
	fi
}
nl=$'\n'

r=pstack:reviewer
expect allow $r 'git diff main...HEAD'
expect allow $r 'git log --oneline -5 | head -3'
expect allow $r 'git status --short 2>&1'
expect allow $r 'git -C /repo show HEAD:README.md'
expect allow $r 'git branch --show-current'
expect allow $r 'git branch --contains abc123'
expect allow $r 'git stash list'
expect allow $r 'git tag --list "v*"'
expect allow $r 'git config --get user.name'
expect allow $r 'git config get user.email'
expect allow $r 'git config --file .gitmodules --get-regexp path'
expect allow $r 'git fetch origin main'
expect allow $r 'git clean -n'
expect allow $r 'git clone https://github.com/o/r /tmp/y'
expect allow $r 'git bisect log'
expect allow $r 'gh pr view 123 --comments'
expect allow $r 'gh api repos/o/r/pulls/1'
expect allow $r 'grep -rn foo src > /dev/null'
expect allow $r 'ls -la && cat README.md'
expect allow $r 'd=$(mktemp -d) && echo notes > "$d/notes.md"'
expect allow $r 'd=$(mktemp -d) && cd "$d" && touch a.txt'
expect allow $r 'cd "$(mktemp -d)" && echo x > notes.md'
expect allow $r 'echo x > "${TMPDIR:-/tmp}/notes.md"'
expect allow $r 'echo x > /tmp/scratch.txt'
expect allow $r 'echo "a > b" | wc -c'
expect allow $r 'echo x >&2'
expect allow $r 'npm test'
expect allow $r 'npm run build'
expect allow $r "sed -n '1,20p' src/a.ts"
expect allow $r "sed -e 's/x/y/i' src/a.ts"
expect allow $r "perl -ne 'print if /x/' src/a.ts"
expect allow $r "perl -Mstrict -we 'print 1'"
expect allow $r "perl -MList::Util=sum -e 'print sum(1, 2)'"
expect allow $r "awk '\$1 > 5' data.txt"
expect allow $r 'find . -name "*.ts" | xargs grep -l foo'
expect allow $r 'find . -name "*.ts" -exec grep -l foo {} +'
expect allow $r 'command -v node'
expect allow $r '(( n > 0 )) && echo positive'
expect allow $r 'for ((i=3; i>0; i--)); do echo $i; done'
expect allow $r 'echo $((1 > 0))'
expect allow $r 'git status # check a -> b'
expect allow $r 'git log | tee >(wc -l)'
expect allow $r "mkdir -p \\${nl}/tmp/review-scratch"
expect allow $r "git stash \\${nl}list"
expect allow $r "git worktree \\${nl}list"
expect allow $r "cat <<EOF > /tmp/x${nl}hello > world.txt${nl}EOF${nl}git status"
expect allow $r "grep foo <<< \"\$x\""

expect deny $r "sed -i '' 's/a/b/' src/a.ts"
expect deny $r "sed -I '' 's/a/b/' src/a.ts"
expect deny $r 'sed -Ei s/a/b/ src/a.ts'
expect deny $r "perl -pi -e 's/a/b/' src/a.ts"
expect deny $r 'git commit -m wip'
expect deny $r 'git -C . checkout main'
expect deny $r 'git stash'
expect deny $r 'git stash pop'
expect deny $r 'git branch feature-x'
expect deny $r 'git branch -D old'
expect deny $r 'git tag v1.0'
expect deny $r 'git config user.name Someone'
expect deny $r 'git apply fix.patch'
expect deny $r 'git bisect start'
expect deny $r 'git clean -fd'
expect deny $r 'FOO=1 git push origin HEAD'
expect deny $r 'gh pr checkout 123'
expect deny $r 'gh pr merge 123 --squash'
expect deny $r 'gh api -X POST repos/o/r/issues -f title=x'
expect deny $r 'gh api repos/o/r/issues -f title=x'
expect deny $r 'echo x > src/a.ts'
expect deny $r 'echo x>>notes.md'
expect deny $r 'cat a | tee out.txt'
expect deny $r 'rm -rf "$PWD/src"'
expect deny $r 'rm -rf "$(pwd)/src"'
expect deny $r 'echo x > "$(git rev-parse --show-toplevel)/REVIEW.md"'
expect deny $r "cat > \"\${CLAUDE_PROJECT_DIR}/notes.md\" <<EOF${nl}x${nl}EOF"
expect deny $r 'cp new.ts "$HOME/project/src/a.ts"'
expect deny $r 'echo "$(rm -rf src)"'
expect deny $r 'npm install left-pad'
expect deny $r 'npm --prefix app install left-pad'
expect deny $r 'pnpm add zod'
expect deny $r 'pnpm --filter web add zod'
expect deny $r 'uv pip install requests'
expect deny $r 'python3 -m pip install requests'
expect deny $r 'rm -rf build'
expect deny $r 'sudo rm -f lockfile'
expect deny $r 'sudo -n rm -rf /opt/x'
expect deny $r 'timeout 60 rm -rf build'
expect deny $r 'mv a.ts b.ts'
expect deny $r 'cp a.ts b.ts'
expect deny $r 'touch new-file.ts'
expect deny $r 'cd /tmp && cd - && touch x'
expect allow $r 'cd /tmp && touch x'
expect deny $r "find . -name '*.orig' -delete"
expect deny $r 'find . -name x -exec rm {} \;'
expect deny $r 'ls | xargs -I {} rm {}'
expect deny $r "git -C /repo \\${nl}checkout main"
expect deny $r "sudo \\${nl}rm -rf build"
expect deny $r "npm \\${nl}install left-pad"
expect deny $r "grep foo <<< \"\$x\"${nl}rm -rf src"
expect deny $r "cat <<EOF > /tmp/x${nl}hello${nl}EOF${nl}echo done > out.txt"
expect deny $r 'rm -rf build' Monitor

expect deny pstack:reviewer-low 'git commit -m wip'
expect deny pstack:reviewer-max 'rm -rf build' Monitor
expect allow pstack:poteto-agent-max 'git commit -m wip'
expect allow pstack-opus-max-review 'git commit -m wip'
expect allow pstack:codex-bridge 'pstack-seat --mode review --prompt /tmp/p.md'
expect allow general-purpose 'rm -rf build'
expect allow "" 'rm -rf build'

if [ "$failures" -ne 0 ]; then
	echo "$failures of $count failed"
	exit 1
fi
echo "all $count passed"
