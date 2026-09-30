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
