---
description: /pstack:how answers through read-only pstack reviewer seats.
max_turns: 30
timeout_seconds: 600
runs: 1
allowed_tools: [Read, Glob, Grep, Agent, Skill]
---

/pstack:how how does this retry loop decide when to stop? The code is below, not in a file.

```ts
export interface RetryOptions {
	maxAttempts: number;
	baseDelayMs: number;
	isRetryable: (error: unknown) => boolean;
}

export async function withRetry<T>(run: () => Promise<T>, options: RetryOptions): Promise<T> {
	let attempt = 0;
	for (;;) {
		attempt++;
		try {
			return await run();
		} catch (error) {
			if (attempt >= options.maxAttempts || !options.isRetryable(error)) throw error;
			await sleep(options.baseDelayMs * 2 ** (attempt - 1));
		}
	}
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
```
