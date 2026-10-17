## 2026-09-26 - Replace Get-Random with CSPRNG

**Vulnerability:** Weak random number generation using Get-Random
**Learning:** Generating passwords using Get-Random is cryptographically insecure because it relies on a PRNG.
**Prevention:** Always use [System.Security.Cryptography.RandomNumberGenerator] with rejection sampling for security-critical randomness such as passwords, tokens, or encryption keys.

## 2026-09-26 - Add Timeouts to External API Calls

**Vulnerability:** Resource Exhaustion / Denial of Service (DoS) due to missing timeouts on external API calls.
**Learning:** `Invoke-RestMethod` and `Invoke-WebRequest` block indefinitely by default if the external server hangs or drops packets without closing the connection.
**Prevention:** Always add a reasonable `-TimeoutSec` parameter (e.g., 5-30s for fast metadata APIs, 120s for general REST endpoints) to prevent scripts from hanging infinitely and exhausting execution resources.

## 2026-10-01 - Get-Random used in internal functions

**Vulnerability:** Weak random number generation using Get-Random
**Learning:** `Get-Random` was used to generate exponential backoff delays. Even though not explicitly cryptographic, policy requires use of CSPRNG everywhere to avoid security analysis noise or future misuse.
**Prevention:** Avoid `Get-Random` entirely. Always use `[System.Security.Cryptography.RandomNumberGenerator]`.

## 2026-10-04 - SQL Escaping Data Mutation
**Vulnerability:** While SQL injection was prevented by replacing single quotes with underscores `Replace("'", "_")` during dynamic query generation for DuckDB, it caused unintended data mutation.
**Learning:** Security fixes shouldn't compromise data integrity. Replacing `'` with `_` protects against injection but corrupts legitimate strings with apostrophes (e.g., "O'Connor" becomes "O_Connor").
**Prevention:** Use standard SQL escaping by replacing a single quote with two single quotes `Replace("'", "''")` when building raw SQL queries, which prevents injection while preserving the original string content.

## 2026-10-18 - SecureString Decryption Memory Leak
**Vulnerability:** Converting SecureString to plain text using `[System.Net.NetworkCredential]` leaves the plain text password in memory longer than necessary and cannot be explicitly cleared.
**Learning:** Decrypting SecureString with `[System.Net.NetworkCredential]::new('', $SecureString).Password` causes the plaintext secret to exist in managed memory, where it's subject to the Garbage Collector's non-deterministic cleanup. If memory is dumped, the plaintext secret might be recoverable.
**Prevention:** Use unmanaged memory handling for decryption by using `[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR()`, reading it with `PtrToStringBSTR()`, and immediately clearing the unmanaged memory using `ZeroFreeBSTR()` inside a `finally` block to minimize plaintext memory exposure.
