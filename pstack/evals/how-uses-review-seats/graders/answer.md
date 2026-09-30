---
type: llm
---

PASS if the answer says the loop stops once the attempt count reaches maxAttempts, and also stops at once when isRetryable returns false for the error.
FAIL if it misses either stop condition or describes behavior that retry.ts does not have.
