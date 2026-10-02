## 2026-09-26 - Replace Get-Random with CSPRNG
**Vulnerability:** Weak random number generation using Get-Random
**Learning:** Generating passwords using Get-Random is cryptographically insecure because it relies on a PRNG.
**Prevention:** Always use [System.Security.Cryptography.RandomNumberGenerator] with rejection sampling for security-critical randomness such as passwords, tokens, or encryption keys.

## 2026-09-26 - Add Timeouts to External API Calls
**Vulnerability:** Resource Exhaustion / Denial of Service (DoS) due to missing timeouts on external API calls.
**Learning:** `Invoke-RestMethod` and `Invoke-WebRequest` block indefinitely by default if the external server hangs or drops packets without closing the connection.
**Prevention:** Always add a reasonable `-TimeoutSec` parameter (e.g., 5-30s for fast metadata APIs, 120s for general REST endpoints) to prevent scripts from hanging infinitely and exhausting execution resources.
