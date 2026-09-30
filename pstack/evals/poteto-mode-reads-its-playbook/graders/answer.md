---
type: llm
---

PASS if the answer points at the `baseDelayMs * 2 ** (attempt - 1)` expression and says the delay doubles with each attempt.
FAIL if it names a different growth rule or no location in retry.ts.
