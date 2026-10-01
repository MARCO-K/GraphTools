## 2026-09-26 - Replace Get-Random with CSPRNG
**Vulnerability:** Weak random number generation using Get-Random
**Learning:** Generating passwords using Get-Random is cryptographically insecure because it relies on a PRNG.
**Prevention:** Always use [System.Security.Cryptography.RandomNumberGenerator] with rejection sampling for security-critical randomness such as passwords, tokens, or encryption keys.
## 2026-10-01 - Get-Random used in internal functions
**Vulnerability:** Weak random number generation using Get-Random
**Learning:** `Get-Random` was used to generate exponential backoff delays. Even though not explicitly cryptographic, policy requires use of CSPRNG everywhere to avoid security analysis noise or future misuse.
**Prevention:** Avoid `Get-Random` entirely. Always use `[System.Security.Cryptography.RandomNumberGenerator]`.
