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

## 2026-10-06 - Insecure SecureString Decryption

**Vulnerability:** Converting `SecureString` to plaintext using `[System.Net.NetworkCredential]` leaves the plaintext secret in unmanaged memory, exposing it to potential memory dumps.
**Learning:** `[System.Net.NetworkCredential]::new('', $Secret).Password` is convenient but does not securely erase the plaintext password from memory after use, which defeats the purpose of using `SecureString` in the first place.
**Prevention:** When decrypting a `SecureString` to plaintext, use `[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR()`, read the string with `PtrToStringBSTR()`, and securely clear the unmanaged memory using `ZeroFreeBSTR()` inside a `finally` block to minimize plaintext memory exposure.

## 2026-10-29 - Prevent SQL Injection via Structural Identifiers in DuckDB

**Vulnerability:** SQL Injection through unsanitized table names.
**Learning:** When dynamically constructing SQL queries in DuckDB, interpolating unvalidated input (like table names) directly into the query exposes the application to SQL injection. Standard parameterization often doesn't work for structural identifiers like table names.
**Prevention:** Enforce strict whitelisting on parameters used as structural identifiers using `[ValidatePattern('^[a-zA-Z0-9_]+$')]` to ensure they only contain safe characters (alphanumeric and underscores) before using them in dynamic SQL construction.
