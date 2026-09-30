#!/usr/bin/env node
// Denies Bash and Monitor commands that change files or repository state in pstack's read-only review seats.
// It catches the slips the reviewer prompt forbids. It is a heuristic, not a sandbox, so the prompt still applies.
import { readFileSync } from "node:fs";

const REVIEW_SEAT = /^(pstack:reviewer|pstack-(opus|sonnet|haiku|fable)-(low|medium|high|xhigh|max)-review)$/;
const SCRATCH_PREFIX = /^(\/dev\/(null|stdout|stderr|tty|fd\/\d+)$|\/tmp(\/|$)|\/private\/tmp(\/|$)|\/var\/folders\/|\/private\/var\/folders\/)/;
const WRITES = "changes the repository";

const GIT_WRITES = new Set([
	"add", "am", "checkout", "cherry-pick", "commit", "gc", "init", "merge", "mv", "prune", "pull", "push",
	"rebase", "reset", "restore", "revert", "rm", "switch", "update-index", "update-ref",
]);
const GH_WRITES = {
	pr: ["checkout", "merge", "close", "reopen", "ready", "edit", "create", "comment", "review", "lock", "unlock", "update-branch"],
	issue: ["create", "close", "reopen", "edit", "comment", "delete", "transfer", "lock", "unlock", "pin", "unpin", "develop"],
	repo: ["clone", "fork", "sync", "create", "delete", "edit", "rename", "archive", "unarchive", "set-default"],
	release: ["create", "delete", "edit", "upload", "delete-asset"],
	label: ["create", "delete", "edit", "clone"],
	workflow: ["run", "enable", "disable"],
	run: ["rerun", "cancel", "delete"],
	secret: ["set", "delete"],
	variable: ["set", "delete"],
};
const INSTALLS = {
	npm: ["install", "i", "ci", "add", "uninstall", "un", "remove", "rm", "update", "up", "link", "publish"],
	pnpm: ["add", "install", "i", "remove", "rm", "update", "up", "link"],
	yarn: ["add", "install", "remove", "upgrade", "up", "link"],
	bun: ["add", "install", "i", "remove", "rm", "update", "link"],
	pip: ["install", "uninstall"],
	pip3: ["install", "uninstall"],
	uv: ["add", "remove", "sync"],
	poetry: ["add", "install", "remove", "update"],
	brew: ["install", "uninstall", "upgrade", "reinstall", "link", "unlink", "tap"],
	cargo: ["add", "install", "remove", "update"],
	go: ["get", "install"],
	gem: ["install", "uninstall"],
	bundle: ["install", "update", "add"],
};
const INSTALL_VALUE_FLAGS = {
	npm: ["--prefix", "-w", "--workspace", "--registry", "--cache", "--userconfig"],
	pnpm: ["--filter", "-F", "-C", "--dir", "--registry", "--store-dir"],
	yarn: ["--cwd", "--registry"],
	bun: ["--cwd", "--filter", "--registry"],
	uv: ["--directory", "--project", "--python", "-p", "--index-url"],
	poetry: ["-C", "--directory", "-P", "--project"],
	cargo: ["--manifest-path", "-Z", "--config", "-C"],
	go: ["-C"],
};
const WRAPPERS = {
	sudo: ["-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T"],
	xargs: ["-I", "-n", "-P", "-L", "-d", "-s", "-E", "-a", "-J", "-R", "-S"],
	env: ["-u", "-C", "-S", "-P"],
	time: ["-o", "-f"],
	nice: ["-n"],
	timeout: ["-s", "-k", "--signal", "--kill-after"],
	nohup: [],
	command: [],
	builtin: [],
	exec: ["-a"],
};
const PATH_WRITERS = new Set(["rm", "rmdir", "touch", "mkdir", "chmod", "chown", "chgrp", "truncate", "unlink", "tee"]);
const DEST_WRITERS = new Set(["cp", "mv", "ln", "install", "rsync"]);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;

// Splits a command line into simple commands, each with its words and the files it redirects output to.
// Commands inside $(...), backticks, and process substitutions come back as their own entries, marked inner.
function parse(command, inner = false) {
	const segments = [];
	const n = command.length;
	let words = [];
	let redirects = [];
	let word = "";
	let quoted = false;
	let heredocs = [];
	const pushWord = () => {
		if (word !== "" || quoted) words.push(word);
		word = "";
		quoted = false;
	};
	const endSegment = () => {
		pushWord();
		if (words.length || redirects.length) segments.push({ words, redirects, inner });
		words = [];
		redirects = [];
	};
	const closeDouble = (open) => {
		for (let j = open + 1; j < n; j++) {
			if (command[j] === "\\") j++;
			else if (command[j] === '"') return j;
		}
		return n;
	};
	// Index just past the `)` that closes the `(` at `open`.
	const closeParen = (open) => {
		let depth = 0;
		for (let j = open; j < n; j++) {
			const c = command[j];
			if (c === "\\") j++;
			else if (c === "'") {
				const e = command.indexOf("'", j + 1);
				j = e === -1 ? n : e;
			} else if (c === '"') j = closeDouble(j);
			else if (c === "(") depth++;
			else if (c === ")" && --depth === 0) return j + 1;
		}
		return n;
	};
	// Reads one word starting at i, for redirect targets and heredoc delimiters.
	const readWord = (i) => {
		while (i < n && (command[i] === " " || command[i] === "\t")) i++;
		let text = "";
		while (i < n) {
			const c = command[i];
			if (c === "'") {
				const e = command.indexOf("'", i + 1);
				const end = e === -1 ? n : e;
				text += command.slice(i + 1, end);
				i = end + 1;
			} else if (c === '"') {
				const end = closeDouble(i);
				text += command.slice(i + 1, end);
				i = end + 1;
			} else if (c === "$" && command[i + 1] === "(") {
				const end = closeParen(i + 1);
				segments.push(...parse(command.slice(i + 2, end - 1), true));
				text += command.slice(i, end);
				i = end;
			} else if (/[\s;|&()<>`]/.test(c)) break;
			else {
				text += c;
				i++;
			}
		}
		return [text, i];
	};

	for (let i = 0; i < n; i++) {
		const c = command[i];
		if (c === "\\") {
			if (command[i + 1] !== "\n" && i + 1 < n) word += command[i + 1];
			i++;
			continue;
		}
		if (c === "'") {
			const e = command.indexOf("'", i + 1);
			const end = e === -1 ? n : e;
			word += command.slice(i + 1, end);
			quoted = true;
			i = end;
			continue;
		}
		if (c === '"') {
			const end = closeDouble(i);
			for (let j = i + 1; j < end; j++) {
				if (command[j] === "\\" && j + 1 < end) {
					if (command[j + 1] !== "\n") word += command[j + 1];
					j++;
				} else if (command[j] === "$" && command[j + 1] === "(" && command[j + 2] !== "(") {
					const close = closeParen(j + 1);
					segments.push(...parse(command.slice(j + 2, close - 1), true));
					word += command.slice(j, close);
					j = close - 1;
				} else word += command[j];
			}
			quoted = true;
			i = end;
			continue;
		}
		if (c === "#" && word === "" && !quoted) {
			const e = command.indexOf("\n", i);
			i = (e === -1 ? n : e) - 1;
			continue;
		}
		if ((c === "(" && command[i + 1] === "(") || (c === "$" && command[i + 1] === "(" && command[i + 2] === "(")) {
			i = closeParen(c === "$" ? i + 1 : i) - 1;
			word += "0";
			continue;
		}
		if (c === "$" && command[i + 1] === "(") {
			const end = closeParen(i + 1);
			segments.push(...parse(command.slice(i + 2, end - 1), true));
			word += command.slice(i, end);
			i = end - 1;
			continue;
		}
		if (c === "`") {
			const e = command.indexOf("`", i + 1);
			const end = e === -1 ? n : e;
			segments.push(...parse(command.slice(i + 1, end), true));
			word += command.slice(i, end + 1);
			i = end;
			continue;
		}
		if ((c === "<" || c === ">") && command[i + 1] === "(") {
			pushWord();
			const end = closeParen(i + 1);
			segments.push(...parse(command.slice(i + 2, end - 1), true));
			i = end - 1;
			continue;
		}
		if (c === "<" && command.startsWith("<<<", i)) {
			pushWord();
			i = readWord(i + 3)[1] - 1;
			continue;
		}
		if (c === "<" && command[i + 1] === "<") {
			pushWord();
			const start = command[i + 2] === "-" ? i + 3 : i + 2;
			const [delimiter, next] = readWord(start);
			heredocs.push(delimiter);
			i = next - 1;
			continue;
		}
		if (c === "<") {
			if (/^\d+$/.test(word)) word = "";
			pushWord();
			i = readWord(command[i + 1] === "&" ? i + 2 : i + 1)[1] - 1;
			continue;
		}
		if (c === ">" || (c === "&" && command[i + 1] === ">")) {
			if (/^\d+$/.test(word)) word = "";
			pushWord();
			let j = c === "&" ? i + 2 : i + 1;
			if (command[j] === ">" || command[j] === "|") j++;
			if (command[j] === "&") {
				i = readWord(j + 1)[1] - 1;
				continue;
			}
			const [target, next] = readWord(j);
			redirects.push(target);
			i = next - 1;
			continue;
		}
		if (c === "\n") {
			endSegment();
			for (const delimiter of heredocs) {
				const lines = command.slice(i + 1).split("\n");
				let skipped = 0;
				let k = 0;
				for (; k < lines.length; k++) {
					skipped += lines[k].length + 1;
					if (lines[k].replace(/^\t+/, "") === delimiter) break;
				}
				i += k < lines.length ? skipped : n;
			}
			heredocs = [];
			continue;
		}
		if (c === ";" || c === "|" || c === "&" || c === "(" || c === ")") {
			endSegment();
			continue;
		}
		if (c === " " || c === "\t") {
			pushWord();
			continue;
		}
		word += c;
	}
	endSegment();
	return segments;
}

// Variables the command itself fills from mktemp, plus TMPDIR, are scratch.
function scratchChecker(command) {
	const vars = new Set(["TMPDIR"]);
	const assigned = /(?:^|[\s;&|(])(?:(?:export|local|readonly)\s+|declare\s+(?:-\w+\s+)*)?([A-Za-z_]\w*)=["']?(?:\$\(|`)\s*mktemp\b/g;
	for (const match of command.matchAll(assigned)) vars.add(match[1]);
	return (path, cwdScratch) => {
		if (SCRATCH_PREFIX.test(path)) return true;
		if (/^(\$\(|`)\s*mktemp\b/.test(path)) return true;
		const variable = path.match(/^\$\{?([A-Za-z_]\w*)/);
		if (variable) return vars.has(variable[1]);
		if (/^[/$~]/.test(path)) return false;
		return cwdScratch;
	};
}

// Drops leading assignments and wrappers such as sudo, env, and xargs, with their flags.
function commandWords(words) {
	let i = 0;
	while (i < words.length && ASSIGNMENT.test(words[i])) i++;
	while (i < words.length && WRAPPERS[words[i]]) {
		const valueFlags = WRAPPERS[words[i]];
		const wrapper = words[i++];
		while (i < words.length && (words[i].startsWith("-") || ASSIGNMENT.test(words[i]))) {
			i += valueFlags.includes(words[i]) ? 2 : 1;
		}
		if (wrapper === "timeout" && i < words.length) i++;
	}
	return words.slice(i);
}

function firstPositional(args, valueFlags = []) {
	for (let k = 0; k < args.length; k++) {
		if (valueFlags.includes(args[k])) k++;
		else if (!args[k].startsWith("-")) return [args[k], args.slice(k + 1)];
	}
	return [undefined, []];
}

function violation(words, redirects, scratch, cwdScratch) {
	for (const target of redirects) {
		if (!scratch(target, cwdScratch)) return `\`> ${target}\` writes a file`;
	}
	const [name, ...args] = commandWords(words);
	if (!name) return null;
	const tool = name.split("/").pop();
	const isScratch = (path) => scratch(path, cwdScratch);
	if (tool === "sed" || tool === "gsed") {
		for (let k = 0; k < args.length; k++) {
			if (args[k] === "-e" || args[k] === "-f") k++;
			else if (args[k] === "--in-place" || args[k].startsWith("--in-place=") || /^-[a-zA-Z]*[iI]/.test(args[k])) {
				return "`sed -i` edits files in place";
			}
		}
		return null;
	}
	if (tool === "perl") {
		for (const arg of args) {
			if (!arg.startsWith("-") || arg.startsWith("--")) continue;
			for (const flag of arg.slice(1)) {
				if (flag === "i") return "`perl -i` edits files in place";
				if ("MmIeE".includes(flag)) break;
			}
		}
		return null;
	}
	if (tool === "git") return gitViolation(args, isScratch);
	if (tool === "gh") return ghViolation(args);
	if (/^python(\d+(\.\d+)*)?$/.test(tool)) {
		const m = args.indexOf("-m");
		if (m !== -1 && args[m + 1] === "pip" && ["install", "uninstall"].includes(args[m + 2])) {
			return "`python -m pip` changes installed packages";
		}
		return null;
	}
	if (INSTALLS[tool]) {
		const [sub, rest] = firstPositional(args, INSTALL_VALUE_FLAGS[tool]);
		if (tool === "uv" && sub === "pip" && ["install", "uninstall"].includes(firstPositional(rest)[0])) {
			return "`uv pip` changes installed packages";
		}
		if (INSTALLS[tool].includes(sub)) return `\`${tool} ${sub}\` changes installed packages`;
		if (tool === "yarn" && sub === undefined) return "`yarn` installs packages";
		return null;
	}
	if (tool === "find") {
		if (args.includes("-delete")) return "`find -delete` deletes files";
		for (let k = 0; k < args.length; k++) {
			if (["-exec", "-execdir", "-ok", "-okdir"].includes(args[k])) {
				const end = args.findIndex((a, m) => m > k && (a === ";" || a === "+"));
				const inside = violation(args.slice(k + 1, end === -1 ? undefined : end), [], scratch, cwdScratch);
				if (inside) return `\`find ${args[k]}\` runs a command that ${inside.replace(/^`[^`]*` /, "")}`;
			}
		}
		return null;
	}
	if (tool === "patch") return args.includes("--dry-run") || args.includes("--check") ? null : "`patch` changes files";
	if (tool === "dd") {
		const of = args.find((a) => a.startsWith("of="));
		return of && !isScratch(of.slice(3)) ? `\`dd ${of}\` writes a file` : null;
	}
	const paths = args.filter((a) => !a.startsWith("-"));
	if (PATH_WRITERS.has(tool)) {
		const target = paths.find((p) => !isScratch(p));
		return target === undefined ? null : `\`${tool} ${target}\` changes files`;
	}
	if (DEST_WRITERS.has(tool)) {
		const target = paths.at(-1);
		return target === undefined || isScratch(target) ? null : `\`${tool}\` into \`${target}\` changes files`;
	}
	return null;
}

function gitViolation(args, isScratch) {
	let k = 0;
	while (k < args.length && args[k].startsWith("-")) {
		k += ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"].includes(args[k]) ? 2 : 1;
	}
	const [sub, ...rest] = args.slice(k);
	if (!sub) return null;
	const flags = rest.filter((a) => a.startsWith("-"));
	const positional = rest.filter((a) => !a.startsWith("-"));
	const listing = flags.some((f) =>
		/^-(a|r|l|v+|n\d*)$|^--(all|remotes|list|contains|no-contains|merged|no-merged|points-at|format|sort|show-current|verbose)/.test(f),
	);
	const writes = {
		clean: () => !rest.some((a) => /^-(n|[a-zA-Z]*n[a-zA-Z]*)$|^--dry-run$/.test(a)),
		clone: () => !(positional.length >= 2 && isScratch(positional.at(-1))),
		apply: () => !rest.some((a) => ["--check", "--stat", "--numstat", "--summary"].includes(a)),
		stash: () => !["list", "show"].includes(positional[0]),
		bisect: () => !["log", "view", "visualize", "help"].includes(positional[0]),
		branch: () =>
			(positional.length > 0 && !listing) ||
			flags.some((f) => /^-(d|D|m|M|c|C|u|f)$|^--(delete|move|copy|force|set-upstream-to|unset-upstream|edit-description)/.test(f)),
		tag: () => positional.length > 0 && !listing,
		worktree: () => positional.length > 0 && positional[0] !== "list",
		remote: () => ["add", "remove", "rm", "rename", "set-url", "set-head", "set-branches", "prune"].includes(positional[0]),
		config: () => gitConfigWrites(rest),
		notes: () => ["add", "append", "copy", "edit", "merge", "remove", "prune"].includes(positional[0]),
		submodule: () => positional.length > 0 && !["status", "summary"].includes(positional[0]),
	}[sub];
	return (writes ? writes() : GIT_WRITES.has(sub)) ? `\`git ${sub}\` ${WRITES}` : null;
}

function gitConfigWrites(rest) {
	if (rest.some((a) => /^--(unset|unset-all|add|replace-all|rename-section|remove-section|edit)$|^-e$/.test(a))) return true;
	if (rest.some((a) => /^(--get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|--list|-l)$/.test(a))) return false;
	const valueFlags = ["--file", "-f", "--blob", "--type", "--default", "--comment", "--value"];
	const positional = [];
	for (let k = 0; k < rest.length; k++) {
		if (valueFlags.includes(rest[k])) k++;
		else if (!rest[k].startsWith("-")) positional.push(rest[k]);
	}
	if (["get", "list"].includes(positional[0])) return false;
	if (["set", "unset", "rename-section", "remove-section", "edit"].includes(positional[0])) return true;
	return positional.length >= 2;
}

function ghViolation(args) {
	let k = 0;
	while (k < args.length && args[k].startsWith("-")) k += ["-R", "--repo"].includes(args[k]) ? 2 : 1;
	const [group, sub] = args.slice(k);
	if (group === "api") {
		const rest = args.slice(k + 1);
		const at = rest.findIndex((a) => a === "-X" || a === "--method");
		const method = at !== -1 ? rest[at + 1] : rest.find((a) => a.startsWith("--method="))?.slice(9);
		if (method && method.toUpperCase() !== "GET") return `\`gh api -X ${method}\` changes GitHub state`;
		if (!method && rest.some((a) => /^(-f|-F|--field|--raw-field|--input)$/.test(a))) return "`gh api` with fields sends a POST";
		return null;
	}
	return GH_WRITES[group]?.includes(sub) ? `\`gh ${group} ${sub}\` ${WRITES} or its GitHub state` : null;
}

function reasons(command) {
	const scratch = scratchChecker(command);
	let cwdScratch = false;
	const found = [];
	for (const { words, redirects, inner } of parse(command)) {
		const [name, ...args] = commandWords(words);
		if (!inner && (name === "cd" || name === "pushd")) {
			cwdScratch = args.length > 0 && args[0] !== "-" && scratch(args[0], cwdScratch);
			continue;
		}
		const reason = violation(words, redirects, scratch, cwdScratch);
		if (reason) found.push(reason);
	}
	return found;
}

function main() {
	let input;
	try {
		input = JSON.parse(readFileSync(0, "utf8"));
	} catch {
		return;
	}
	if (!["Bash", "Monitor"].includes(input.tool_name) || !REVIEW_SEAT.test(input.agent_type ?? "")) return;
	const command = input.tool_input?.command;
	if (typeof command !== "string") return;
	const found = reasons(command);
	if (found.length === 0) return;
	process.stdout.write(
		JSON.stringify({
			hookSpecificOutput: {
				hookEventName: "PreToolUse",
				permissionDecision: "deny",
				permissionDecisionReason: `pstack review seats are read-only, and ${found.join(", ")}. Put scratch files in a directory from \`mktemp -d\`.`,
			},
		}),
	);
}

main();
